// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {
    IERC20MetadataUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IBeefyOracle} from "./interfaces/IBeefyOracle.sol";
import {BytesLib} from "./utils/BytesLib.sol";

/// @title Beefy Swapper
/// @author Beefy, @kexley
/// @notice Centralized swapper
contract BeefySwapper is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using BytesLib for bytes;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Price update failed for a token
    error PriceFailed(address token);

    /// @dev No swap data has been set by the owner
    error NoSwapData(address fromToken, address toToken);

    /// @dev Swap call failed
    error SwapFailed(address router, bytes data);

    /// @dev Not enough output was returned from the swap
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);

    /// @dev Stored data for a swap
    struct SwapInfo {
        address router;
        bytes data;
        uint256 amountIndex;
        uint256 minIndex;
        int8 minAmountSign;
    }

    /// @notice Stored swap info for a token pair
    mapping(address => mapping(address => SwapInfo)) public swapInfo;

    /// @notice Oracle used to calculate the minimum output of a swap
    IBeefyOracle public oracle;

    /// @notice Minimum acceptable percentage slippage output in 18 decimals
    uint256 public slippage;

    event Swap(
        address indexed caller, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );

    event SetSwapInfo(address indexed fromToken, address indexed toToken, SwapInfo swapInfo);
    event SetOracle(address oracle);
    event SetSlippage(uint256 slippage);

    function initialize(address _oracle, uint256 _slippage) external initializer {
        __Ownable_init();
        oracle = IBeefyOracle(_oracle);
        slippage = _slippage;
    }

    /// @notice Swap between two tokens with slippage calculated using the oracle
    function swap(address _fromToken, address _toToken, uint256 _amountIn) external returns (uint256 amountOut) {
        uint256 minAmountOut = _getAmountOut(_fromToken, _toToken, _amountIn);
        amountOut = _swap(_fromToken, _toToken, _amountIn, minAmountOut);
    }

    /// @notice Swap between two tokens with caller-provided slippage (no oracle needed)
    function swap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut)
        external
        returns (uint256 amountOut)
    {
        amountOut = _swap(_fromToken, _toToken, _amountIn, _minAmountOut);
    }

    /// @notice Get the estimated amount out (requires oracle)
    function getAmountOut(address _fromToken, address _toToken, uint256 _amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        (uint256 fromPrice, uint256 toPrice) = (oracle.getPrice(_fromToken), oracle.getPrice(_toToken));
        uint8 decimals0 = IERC20MetadataUpgradeable(_fromToken).decimals();
        uint8 decimals1 = IERC20MetadataUpgradeable(_toToken).decimals();
        amountOut = _calculateAmountOut(_amountIn, fromPrice, toPrice, decimals0, decimals1);
    }

    function _getAmountOut(address _fromToken, address _toToken, uint256 _amountIn)
        private
        returns (uint256 amountOut)
    {
        (uint256 fromPrice, uint256 toPrice) = _getFreshPrice(_fromToken, _toToken);
        uint8 decimals0 = IERC20MetadataUpgradeable(_fromToken).decimals();
        uint8 decimals1 = IERC20MetadataUpgradeable(_toToken).decimals();
        uint256 slippedAmountIn = _amountIn * slippage / 1 ether;
        amountOut = _calculateAmountOut(slippedAmountIn, fromPrice, toPrice, decimals0, decimals1);
    }

    function _swap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut)
        private
        returns (uint256 amountOut)
    {
        IERC20MetadataUpgradeable(_fromToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _executeSwap(_fromToken, _toToken, _amountIn, _minAmountOut);
        amountOut = IERC20MetadataUpgradeable(_toToken).balanceOf(address(this));
        if (amountOut < _minAmountOut) revert SlippageExceeded(amountOut, _minAmountOut);
        IERC20MetadataUpgradeable(_toToken).safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, _fromToken, _toToken, _amountIn, amountOut);
    }

    function _executeSwap(address _fromToken, address _toToken, uint256 _amountIn, uint256 _minAmountOut) private {
        SwapInfo memory swapData = swapInfo[_fromToken][_toToken];
        address router = swapData.router;
        if (router == address(0)) revert NoSwapData(_fromToken, _toToken);
        bytes memory data = swapData.data;

        data = _insertData(data, swapData.amountIndex, abi.encode(_amountIn));

        bytes memory minAmountData = swapData.minAmountSign >= 0
            ? abi.encode(_minAmountOut)
            // casting to 'int256' is safe: _minAmountOut is a token amount bounded by total supply (< 2^255)
            // forge-lint: disable-next-line(unsafe-typecast)
            : abi.encode(-int256(_minAmountOut));

        data = _insertData(data, swapData.minIndex, minAmountData);

        IERC20MetadataUpgradeable(_fromToken).forceApprove(router, type(uint256).max);
        (bool success,) = router.call(data);
        if (!success) revert SwapFailed(router, data);
    }

    function _insertData(bytes memory _data, uint256 _index, bytes memory _newData)
        private
        pure
        returns (bytes memory data)
    {
        data = bytes.concat(
            bytes.concat(_data.slice(0, _index), _newData), _data.slice(_index + 32, _data.length - (_index + 32))
        );
    }

    function _getFreshPrice(address _fromToken, address _toToken) private returns (uint256 fromPrice, uint256 toPrice) {
        bool success;
        (fromPrice, success) = oracle.getFreshPrice(_fromToken);
        if (!success) revert PriceFailed(_fromToken);
        (toPrice, success) = oracle.getFreshPrice(_toToken);
        if (!success) revert PriceFailed(_toToken);
    }

    function _calculateAmountOut(
        uint256 _amountIn,
        uint256 _price0,
        uint256 _price1,
        uint8 _decimals0,
        uint8 _decimals1
    ) private pure returns (uint256 amountOut) {
        amountOut = _amountIn * (_price0 * 10 ** _decimals1) / (_price1 * 10 ** _decimals0);
    }

    function setSwapInfo(address _fromToken, address _toToken, SwapInfo calldata _swapInfo) external onlyOwner {
        swapInfo[_fromToken][_toToken] = _swapInfo;
        emit SetSwapInfo(_fromToken, _toToken, _swapInfo);
    }

    function setSwapInfos(address[] calldata _fromTokens, address[] calldata _toTokens, SwapInfo[] calldata _swapInfos)
        external
        onlyOwner
    {
        uint256 tokenLength = _fromTokens.length;
        for (uint256 i; i < tokenLength;) {
            swapInfo[_fromTokens[i]][_toTokens[i]] = _swapInfos[i];
            emit SetSwapInfo(_fromTokens[i], _toTokens[i], _swapInfos[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = IBeefyOracle(_oracle);
        emit SetOracle(_oracle);
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        if (_slippage > 1 ether) _slippage = 1 ether;
        slippage = _slippage;
        emit SetSlippage(_slippage);
    }
}
