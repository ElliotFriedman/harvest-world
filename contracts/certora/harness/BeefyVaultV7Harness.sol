// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IStrategyV7} from "../../src/interfaces/IStrategyV7.sol";
import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";

// ---------------------------------------------------------------------------
// MockERC20 — minimal ERC-20 used as the underlying "want" token.
// Certora summarises external token calls, but having a concrete
// implementation lets the prover track balances precisely.
// ---------------------------------------------------------------------------
contract MockERC20 is IERC20Upgradeable {
    string public name;
    string public symbol;
    uint8  public decimals;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
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
        require(_allowances[from][msg.sender] >= amount, "ERC20: insufficient allowance");
        _allowances[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        _balances[from] -= amount;
        _balances[to]   += amount;
        emit Transfer(from, to, amount);
    }

    // Test helper — lets specs mint tokens into arbitrary accounts.
    function mint(address to, uint256 amount) external {
        _balances[to]  += amount;
        _totalSupply   += amount;
        emit Transfer(address(0), to, amount);
    }
}

// ---------------------------------------------------------------------------
// MockStrategy — minimal IStrategyV7 implementation.
//
// The prover treats external calls as havoc sources by default.  By
// providing a concrete implementation we give the prover a fixed model
// so it can reason precisely about `balance()` and share arithmetic.
//
// Key design choices:
//   • `_strategyBalance` is a ghost-visible storage slot (plain uint256).
//   • `want()` always returns the same token as the vault.
//   • `deposit()` / `withdraw()` move tokens between strategy and vault.
//   • `harvest()` increases `_strategyBalance` (models yield accrual).
//   • `beforeDeposit()` is a no-op (no front-running manipulation).
// ---------------------------------------------------------------------------
contract MockStrategy is IStrategyV7 {
    address public immutable vaultAddr;
    IERC20Upgradeable public immutable wantToken;

    // Total underlying held by (or deployed by) this strategy.
    // Certora rules can read this directly through the harness helper.
    uint256 public strategyBalance;

    constructor(address _vault, address _want) {
        vaultAddr   = _vault;
        wantToken   = IERC20Upgradeable(_want);
    }

    // ---- IStrategyV7 --------------------------------------------------------

    function vault()        external view override returns (address)           { return vaultAddr; }
    function want()         external view override returns (IERC20Upgradeable) { return wantToken; }
    function beforeDeposit()external override {}
    function paused()       external pure  override returns (bool)             { return false; }

    /// @dev Called by vault.earn() — pull tokens from vault into strategy.
    function deposit() external override {
        uint256 bal = wantToken.balanceOf(msg.sender);
        if (bal > 0) {
            wantToken.transferFrom(msg.sender, address(this), bal);
            strategyBalance += bal;
        }
    }

    /// @dev Called by vault.withdraw() — send `_amount` back to vault.
    function withdraw(uint256 _amount) external override {
        uint256 avail = wantToken.balanceOf(address(this));
        uint256 toSend = _amount <= avail ? _amount : avail;
        if (toSend > 0) {
            strategyBalance -= toSend;
            wantToken.transfer(msg.sender, toSend);
        }
    }

    /// @dev balanceOf() is the canonical view queried by BeefyVaultV7.balance().
    function balanceOf()     external view override returns (uint256) { return strategyBalance; }
    function balanceOfWant() external view override returns (uint256) { return wantToken.balanceOf(address(this)); }
    function balanceOfPool() external view override returns (uint256) { return 0; }

    /// @dev harvest() — models yield: increase strategyBalance without touching
    ///      token balances, simulating external yield accrual.
    ///      The prover can call this to check that price-per-share is non-decreasing.
    function harvest()     external override { /* yield modelled via addYield() below */ }
    function retireStrat() external override { strategyBalance = 0; }
    function panic()       external override {}
    function pause()       external override {}
    function unpause()     external override {}

    // ---- Test helpers -------------------------------------------------------

    /// @dev Simulate yield accrual without token movement.
    ///      Call this before asserting getPricePerFullShare() is non-decreasing.
    function addYield(uint256 _amount) external {
        strategyBalance += _amount;
    }

    /// @dev Allow the vault (or tests) to mint tokens directly into strategy
    ///      for setup purposes.
    function setBalance(uint256 _balance) external {
        strategyBalance = _balance;
    }
}

// ---------------------------------------------------------------------------
// BeefyVaultV7Harness — thin wrapper that:
//   1. Exposes internal/private state as external view functions.
//   2. Wires up MockStrategy so Certora can reason about both sides.
//   3. Overrides PERMIT2.transferFrom with a direct token pull so the
//      prover doesn't need to model the Permit2 singleton contract.
// ---------------------------------------------------------------------------
contract BeefyVaultV7Harness is BeefyVaultV7 {

    // ---- Harness-level helpers ----------------------------------------------

    /// @notice Underlying token balance held directly by this vault.
    function vaultTokenBalance() external view returns (uint256) {
        return want().balanceOf(address(this));
    }

    /// @notice Strategy balance as reported by strategy.balanceOf().
    function strategyTokenBalance() external view returns (uint256) {
        return strategy.balanceOf();
    }

    /// @notice balance() = vault token balance + strategy.balanceOf()
    ///         Exposed for use in spec `balance()` ghost.
    function totalBalance() external view returns (uint256) {
        return balance();
    }

    /// @notice Number of shares held by a specific account.
    function sharesOf(address _account) external view returns (uint256) {
        return balanceOf(_account);
    }

    /// @notice Current owner of the vault (from OwnableUpgradeable).
    function currentOwner() external view returns (address) {
        return owner();
    }

    /// @notice Expose totalSupply() for use from spec without ambiguity.
    function vaultTotalSupply() external view returns (uint256) {
        return totalSupply();
    }

    /// @notice getPricePerFullShare proxy — useful as a named entry point.
    function pricePerShare() external view returns (uint256) {
        return getPricePerFullShare();
    }

    // ---- Permit2 bypass for verification ------------------------------------
    //
    // PERMIT2 is a constant pointing to an external singleton.  The prover
    // treats calls to unmodelled externals as havoc.  We override `deposit()`
    // here to call `want().transferFrom()` directly so the prover can track
    // the token balance precisely.
    //
    // NOTE: This only changes how tokens are pulled.  The share minting
    // arithmetic, reentrancy guard, and `earn()` call are unchanged.
    //
    function deposit(uint256 _amount) public override nonReentrant {
        strategy.beforeDeposit();

        uint256 _pool = balance();
        // Direct transferFrom instead of Permit2 (prover-friendly).
        want().transferFrom(msg.sender, address(this), _amount);

        uint256 shares = totalSupply() == 0 ? _amount : (_amount * totalSupply()) / _pool;
        _mint(msg.sender, shares);
        earn();
    }
}
