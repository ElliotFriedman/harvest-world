// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBeefySwapper} from "../../src/interfaces/IBeefySwapper.sol";

contract MockBeefySwapper is IBeefySwapper {
    using SafeERC20 for IERC20;

    // tokenFrom => tokenTo => rate (output per 1e18 input, scaled to 1e18 = 1:1)
    mapping(address => mapping(address => uint256)) public rates;

    uint256 public swapCallCount;

    function setSwapRate(address from, address to, uint256 rate) external {
        rates[from][to] = rate;
    }

    function swap(address fromToken, address toToken, uint256 amountIn) external override returns (uint256 amountOut) {
        return _doSwap(fromToken, toToken, amountIn);
    }

    function swap(address fromToken, address toToken, uint256 amountIn, uint256)
        external
        override
        returns (uint256 amountOut)
    {
        return _doSwap(fromToken, toToken, amountIn);
    }

    function getAmountOut(address fromToken, address toToken, uint256 amountIn) public view override returns (uint256) {
        uint256 rate = rates[fromToken][toToken];
        if (rate == 0) return amountIn; // 1:1 fallback
        return amountIn * rate / 1e18;
    }

    function swapInfo(address, address)
        external
        pure
        override
        returns (address router, bytes calldata data, uint256 amountIndex, uint256 minIndex, int8 minAmountSign)
    {
        // calldata returns cannot be assigned in pure functions; return empty via assembly
        assembly {
            router := 0
            data.offset := 0
            data.length := 0
            amountIndex := 0
            minIndex := 0
            minAmountSign := 0
        }
    }

    function _doSwap(address fromToken, address toToken, uint256 amountIn) internal returns (uint256 amountOut) {
        swapCallCount++;
        IERC20(fromToken).safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = getAmountOut(fromToken, toToken, amountIn);
        IERC20(toToken).safeTransfer(msg.sender, amountOut);
    }
}
