// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/interfaces/IERC4626.sol";

/// @dev Minimal ERC4626 mock with a configurable exchange rate.
///      setExchangeRate(1.05e18) simulates 5% yield accrual.
contract MockMorphoVault is ERC20, IERC4626 {
    using SafeERC20 for IERC20;

    IERC20 private immutable _underlying;
    uint8 private immutable _assetDecimals;

    /// @notice Shares-to-assets rate, scaled by 1e18. Starts at 1:1.
    uint256 public exchangeRate;

    constructor(address asset_, string memory name_, string memory symbol_, uint8 assetDecimals_)
        ERC20(name_, symbol_)
    {
        _underlying = IERC20(asset_);
        _assetDecimals = assetDecimals_;
        exchangeRate = 1e18;
    }

    // ── IERC4626 metadata ────────────────────────────────────────────────────

    function asset() external view override returns (address) {
        return address(_underlying);
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _assetDecimals;
    }

    // ── IERC4626 accounting ──────────────────────────────────────────────────

    function totalAssets() public view override returns (uint256) {
        return convertToAssets(totalSupply());
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return assets * 1e18 / exchangeRate;
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return shares * exchangeRate / 1e18;
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        return _mulDivUp(shares, exchangeRate, 1e18);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _mulDivUp(assets, 1e18, exchangeRate);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function maxDeposit(address) external pure override returns (uint256) { return type(uint256).max; }
    function maxMint(address) external pure override returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address owner_) external view override returns (uint256) { return convertToAssets(balanceOf(owner_)); }
    function maxRedeem(address owner_) external view override returns (uint256) { return balanceOf(owner_); }

    // ── IERC4626 mutating ────────────────────────────────────────────────────

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        shares = previewDeposit(assets);
        _underlying.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {
        assets = previewMint(shares);
        _underlying.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner_) external override returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _burn(owner_, shares);
        _underlying.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner_) external override returns (uint256 assets) {
        assets = previewRedeem(shares);
        _burn(owner_, shares);
        _underlying.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    // ── Test helpers ─────────────────────────────────────────────────────────

    /// @notice Simulate yield by increasing the share price.
    /// @param rate New rate, e.g. 1.05e18 for 5% yield.
    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    function _mulDivUp(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return (a * b + c - 1) / c;
    }
}
