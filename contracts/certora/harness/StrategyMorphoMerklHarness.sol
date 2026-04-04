// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin-4/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-5/contracts/token/ERC20/IERC20.sol";
import {IMerklClaimer} from "../../src/interfaces/IMerklClaimer.sol";
import {StrategyMorphoMerkl, BaseAllToNativeFactoryStrat} from "../../src/StrategyMorphoMerkl.sol";

// =============================================================================
// MockERC20Simple — minimal ERC-20 used as want token and as NATIVE (WETH).
//
// Unlike the vault harness we use a standalone contract here because the
// strategy interacts with two ERC-20 tokens (want and NATIVE) that must be
// independently tracked by the prover.
// =============================================================================
contract MockERC20Simple is IERC20 {
    string  public name;
    string  public symbol;
    uint8   public decimals;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _dec) {
        name     = _name;
        symbol   = _symbol;
        decimals = _dec;
    }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        // max-uint means infinite approval (forceApprove pattern)
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ERC20: insufficient allowance");
            _allowances[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function forceApprove(address spender, uint256 amount) external {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        _balances[from] -= amount;
        _balances[to]   += amount;
        emit Transfer(from, to, amount);
    }

    // ---- Test helpers -------------------------------------------------------

    /// @dev Mint tokens into an account (used by spec setup).
    function mint(address to, uint256 amount) external {
        _balances[to]  += amount;
        _totalSupply   += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @dev Burn tokens from an account (used by spec setup).
    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        _balances[from] -= amount;
        _totalSupply    -= amount;
        emit Transfer(from, address(0), amount);
    }
}

// =============================================================================
// MockMorphoVault — minimal ERC-4626 vault.
//
// Maintains a precise mapping of shares to assets so the prover can track
// balanceOfPool() across calls without NONDET approximation.
//
// Exchange rate: 1 share = (totalAssets / totalShares) assets, defaulting to
// 1:1.  addYieldToMorpho() increases totalAssets without changing shares —
// this models Morpho earning interest.
// =============================================================================
contract MockMorphoVault is IERC4626 {
    IERC20  public immutable _asset;

    mapping(address => uint256) private _shares;
    uint256 private _totalShares;
    uint256 private _totalAssets;  // underlying "deposited + yield"

    constructor(address assetToken) {
        _asset = IERC20(assetToken);
    }

    // ---- IERC4626 view -------------------------------------------------------

    function asset() external view override returns (address) { return address(_asset); }
    function totalAssets() external view override returns (uint256) { return _totalAssets; }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        if (_totalShares == 0 || _totalAssets == 0) return assets;
        return assets * _totalShares / _totalAssets;
    }

    function convertToAssets(uint256 shares) external view override returns (uint256) {
        if (_totalShares == 0) return 0;
        return shares * _totalAssets / _totalShares;
    }

    function maxDeposit(address) external pure override returns (uint256) { return type(uint256).max; }
    function maxMint(address)    external pure override returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address owner) external view override returns (uint256) {
        return _shares[owner] * _totalAssets / (_totalShares == 0 ? 1 : _totalShares);
    }
    function maxRedeem(address owner) external view override returns (uint256) { return _shares[owner]; }

    function previewDeposit(uint256 assets) external view override returns (uint256) {
        if (_totalShares == 0 || _totalAssets == 0) return assets;
        return assets * _totalShares / _totalAssets;
    }

    function previewMint(uint256 shares) external view override returns (uint256) {
        if (_totalShares == 0) return shares;
        return shares * _totalAssets / _totalShares;
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        if (_totalAssets == 0) return 0;
        return assets * _totalShares / _totalAssets;
    }

    function previewRedeem(uint256 shares) external view override returns (uint256) {
        if (_totalShares == 0) return 0;
        return shares * _totalAssets / _totalShares;
    }

    // ---- IERC4626 state-changing --------------------------------------------

    function deposit(uint256 assets, address receiver) external override returns (uint256 sharesOut) {
        _asset.transferFrom(msg.sender, address(this), assets);
        if (_totalShares == 0 || _totalAssets == 0) {
            sharesOut = assets;
        } else {
            sharesOut = assets * _totalShares / _totalAssets;
        }
        _shares[receiver] += sharesOut;
        _totalShares      += sharesOut;
        _totalAssets      += assets;
        emit Deposit(msg.sender, receiver, assets, sharesOut);
    }

    function mint(uint256 shares, address receiver) external override returns (uint256 assetsIn) {
        assetsIn = (_totalShares == 0) ? shares : shares * _totalAssets / _totalShares;
        _asset.transferFrom(msg.sender, address(this), assetsIn);
        _shares[receiver] += shares;
        _totalShares      += shares;
        _totalAssets      += assetsIn;
        emit Deposit(msg.sender, receiver, assetsIn, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 sharesIn) {
        require(_totalAssets > 0, "empty vault");
        sharesIn = assets * _totalShares / _totalAssets;
        require(_shares[owner] >= sharesIn, "ERC4626: insufficient shares");
        _shares[owner] -= sharesIn;
        _totalShares   -= sharesIn;
        _totalAssets   -= assets;
        _asset.transfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, sharesIn);
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assetsOut) {
        require(_shares[owner] >= shares, "ERC4626: insufficient shares");
        assetsOut = (_totalShares == 0) ? 0 : shares * _totalAssets / _totalShares;
        _shares[owner] -= shares;
        _totalShares   -= shares;
        _totalAssets   -= assetsOut;
        _asset.transfer(receiver, assetsOut);
        emit Withdraw(msg.sender, receiver, owner, assetsOut, shares);
    }

    // ---- Minimal ERC-20 surface (shares token) ------------------------------

    function name()     external pure returns (string memory) { return "Mock Morpho Vault"; }
    function symbol()   external pure returns (string memory) { return "mMV"; }
    function decimals() external pure returns (uint8)         { return 18; }

    function totalSupply() external view override returns (uint256) { return _totalShares; }

    function balanceOf(address account) external view override returns (uint256) {
        return _shares[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(_shares[msg.sender] >= amount, "ERC4626: insufficient shares");
        _shares[msg.sender] -= amount;
        _shares[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address, address) external pure override returns (uint256) { return 0; }

    function approve(address spender, uint256 amount) external override returns (bool) {
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(_shares[from] >= amount, "ERC4626: insufficient shares");
        _shares[from] -= amount;
        _shares[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // ---- Test helpers -------------------------------------------------------

    /// @dev Simulate Morpho yield: add assets without minting new shares.
    ///      This increases the share:asset exchange rate, modelling interest accrual.
    function addYield(uint256 yieldAmount) external {
        _totalAssets += yieldAmount;
    }

    /// @dev Direct balance query used by harness getters.
    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }
}

// =============================================================================
// MockBeefySwapper — deterministic no-op swapper.
//
// Returns amountIn as amountOut (1:1 swap) to keep arithmetic predictable
// during verification.  Real slippage is a production concern; for proving
// access control, accounting, and monotonicity properties a 1:1 swap is the
// simplest valid model.
// =============================================================================
// MockBeefySwapper does NOT formally implement IBeefySwapper because the
// interface's swapInfo() returns `bytes calldata` which is only valid as
// a function *parameter* type, not a return type (Solidity 0.8 restriction).
// The strategy calls swapper via IBeefySwapper(swapper).swap(...) and the
// Certora spec summarises all swap() calls as NONDET anyway, so the interface
// inheritance is not required for correctness.
contract MockBeefySwapper {
    /// @dev 3-arg overload used by BaseAllToNativeFactoryStrat._swap(from, to).
    function swap(address fromToken, address toToken, uint256 amountIn)
        external
        returns (uint256)
    {
        // Move tokens through the mock to satisfy token-balance accounting.
        // In specs where swap() is NONDET-summarised this body is not executed.
        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);
        IERC20(toToken).transfer(msg.sender, amountIn);
        return amountIn;
    }

    /// @dev 4-arg overload used by BaseAllToNativeFactoryStrat._swap(from, to, amount).
    function swap(address fromToken, address toToken, uint256 amountIn, uint256 /*minAmountOut*/)
        external
        returns (uint256)
    {
        IERC20(fromToken).transferFrom(msg.sender, address(this), amountIn);
        IERC20(toToken).transfer(msg.sender, amountIn);
        return amountIn;
    }

    function getAmountOut(address, address, uint256 amountIn)
        external
        pure
        returns (uint256)
    {
        return amountIn;
    }
}

// =============================================================================
// MockMerklClaimer — records the most recent claim call so specs can inspect
// which arguments were passed.  Does NOT transfer tokens; reward token
// balances are injected directly in harness helpers.
// =============================================================================
contract MockMerklClaimer is IMerklClaimer {
    address public lastCalledClaimer;   // always address(this) — self-marker
    address[] public lastUsers;
    address[] public lastTokens;
    uint256   public claimCallCount;

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata, /*amounts*/
        bytes32[][] calldata /*proofs*/
    ) external override {
        lastCalledClaimer = address(this);
        claimCallCount   += 1;
        // Store first entry for easy access in specs.
        if (users.length > 0) lastUsers  = users;
        if (tokens.length > 0) lastTokens = tokens;
    }
}

// =============================================================================
// MockVault — minimal vault address that the strategy trusts for
// deposit()/withdraw()/retireStrat() calls.
//
// Used to exercise vault-only access control rules.
// =============================================================================
contract MockVault {
    StrategyMorphoMerklHarness public strategy;

    constructor(address _strategy) {
        strategy = StrategyMorphoMerklHarness(payable(_strategy));
    }

    function callDeposit() external {
        strategy.deposit();
    }

    function callWithdraw(uint256 amount) external {
        strategy.withdraw(amount);
    }

    function callRetireStrat() external {
        strategy.retireStrat();
    }

    function callBeforeDeposit() external {
        strategy.beforeDeposit();
    }
}

// =============================================================================
// StrategyMorphoMerklHarness
//
// Inherits the real StrategyMorphoMerkl and adds:
//   1. View helpers exposing internal storage slots to the spec.
//   2. An initializer that wires up all mocks in one call (avoids needing
//      the prover to model the upgradeable proxy constructor).
//   3. addYieldToMorpho() — tells the mock vault to simulate earned interest.
//   4. injectRewardTokens() — mints reward tokens into the strategy's balance
//      so harvest scenarios can be set up without actual Merkl claims.
// =============================================================================
contract StrategyMorphoMerklHarness is StrategyMorphoMerkl {

    // ---- One-shot initializer -----------------------------------------------

    /// @notice Initialise the strategy with all mocks pre-wired.
    ///         The vault address is provided externally so the spec can link
    ///         a MockVault instance.
    function initializeForVerification(
        address _morphoVault,
        address _claimer,
        address _want,
        address _swapper,
        address _vault,
        address _strategist,
        address _feeRecipient,
        address[] calldata _rewards
    ) external {
        Addresses memory addrs = Addresses({
            want:         _want,
            depositToken: address(0),   // no intermediate deposit token — direct
            vault:        _vault,
            swapper:      _swapper,
            strategist:   _strategist,
            feeRecipient: _feeRecipient
        });
        // Call the real initializer (sets owner = msg.sender via __Ownable_init)
        this.initialize(_morphoVault, _claimer, false, _rewards, addrs);
    }

    // ---- Internal state getters (not on the base contract's public surface) --

    /// @notice Total pending locked profit (before any decay).
    function getTotalLocked() external view returns (uint256) {
        return totalLocked;
    }

    /// @notice Lock duration in seconds.
    function getLockDuration() external view returns (uint256) {
        return lockDuration;
    }

    /// @notice Timestamp of the most recent successful harvest.
    function getLastHarvest() external view returns (uint256) {
        return lastHarvest;
    }

    /// @notice Whether harvestOnDeposit is enabled.
    function getHarvestOnDeposit() external view returns (bool) {
        return harvestOnDeposit;
    }

    /// @notice Current owner (alias for OwnableUpgradeable.owner()).
    function currentOwner() external view returns (address) {
        return owner();
    }

    /// @notice Shares of morphoVault held by this strategy.
    function morphoSharesHeld() external view returns (uint256) {
        return morphoVault.balanceOf(address(this));
    }

    // ---- Yield simulation helpers -------------------------------------------

    /// @notice Inject yield into the underlying Morpho vault mock.
    ///         The mock's addYield() increases totalAssets without minting
    ///         new shares, which raises convertToAssets() for all shareholders.
    ///         Call this before running harvest-scenario rules.
    function addYieldToMorpho(uint256 yieldAmount) external {
        MockMorphoVault(address(morphoVault)).addYield(yieldAmount);
    }

    /// @notice Directly mint reward tokens into this contract's balance.
    ///         Simulates Merkl having distributed tokens that are now claimable
    ///         without requiring a full Merkl proof verification in the spec.
    function injectRewardTokens(address rewardToken, uint256 amount) external {
        MockERC20Simple(rewardToken).mint(address(this), amount);
    }

    /// @notice Expose the claimer's call count so specs can verify it was
    ///         invoked exactly once (or not at all) during harvest.
    function claimCallCount() external view returns (uint256) {
        return MockMerklClaimer(address(claimer)).claimCallCount();
    }

    /// @notice Return the claimer address for identity checks in specs.
    function claimerAddress() external view returns (address) {
        return address(claimer);
    }

    // ---- lockedProfit re-exposure (already public but aliased for clarity) --

    /// @notice Alias for lockedProfit() — useful in spec `require` preconditions.
    function currentLockedProfit() external view returns (uint256) {
        return lockedProfit();
    }
}
