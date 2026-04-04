// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IBeefyOracle} from "../../src/interfaces/IBeefyOracle.sol";
import {BeefySwapper} from "../../src/BeefySwapper.sol";

// =============================================================================
// MockOracle — concrete IBeefyOracle implementation.
//
// Design rationale:
//   Certora treats calls to unmodelled external contracts as NONDET (arbitrary
//   value, arbitrary side-effects).  For slippage-protection rules we need the
//   oracle to return *specific* configurable prices so the prover can reason
//   about the arithmetic relationship:
//
//     minAmountOut = amountIn * slippage / 1e18
//                 * fromPrice / toPrice
//                 * 10^decimalsTo / 10^decimalsFrom
//
//   MockOracle stores per-token prices in a mapping.  Tests set them via
//   setPrice().  getFreshPrice() always succeeds (returns (price, true)).
//   A price of 0 is left as the "unset / unsupported" sentinel; the spec
//   rules that exercise oracle paths explicitly set non-zero prices.
// =============================================================================
contract MockOracle is IBeefyOracle {
    mapping(address => uint256) public prices;

    /// @notice Configure the price for a token (18-decimal USD value).
    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    // ---- IBeefyOracle --------------------------------------------------------

    function getPrice(address token) external view override returns (uint256) {
        return prices[token];
    }

    function getPrice(address[] calldata tokens) external view override returns (uint256[] memory result) {
        result = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            result[i] = prices[tokens[i]];
        }
    }

    function getFreshPrice(address token) external view override returns (uint256 price, bool success) {
        price   = prices[token];
        success = price != 0;
    }

    function getFreshPrice(address[] calldata tokens)
        external
        view
        override
        returns (uint256[] memory result, bool[] memory successes)
    {
        result    = new uint256[](tokens.length);
        successes = new bool[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            result[i]    = prices[tokens[i]];
            successes[i] = result[i] != 0;
        }
    }
}

// =============================================================================
// MockERC20Swappable — minimal ERC-20 with configurable decimals.
//
// Used as fromToken / toToken in swap scenarios.  The harness needs concrete
// tokens so the prover can track balance changes with precision.
//
// Includes forceApprove (infinite approval pattern used by BeefySwapper).
// =============================================================================
contract MockERC20Swappable is IERC20MetadataUpgradeable {
    string  public override name;
    string  public override symbol;
    uint8   public override decimals;

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
        // Honour the infinite-approval (forceApprove) pattern.
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ERC20: insufficient allowance");
            _allowances[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        _balances[from] -= amount;
        _balances[to]   += amount;
        emit Transfer(from, to, amount);
    }

    // ---- Test helpers -------------------------------------------------------

    /// @dev Mint tokens into an account for spec setup.
    function mint(address to, uint256 amount) external {
        _balances[to]  += amount;
        _totalSupply   += amount;
        emit Transfer(address(0), to, amount);
    }
}

// =============================================================================
// MockRouter — records the most recent call data so specs can inspect
// what the swapper sent, and optionally mints toToken into the swapper to
// simulate a successful swap output.
//
// The router is the external contract that BeefySwapper delegates the actual
// swap to.  In Certora the router call is summarised as NONDET in the spec,
// but a concrete mock is still required so the linker can resolve the address.
//
// IMPORTANT: `execute()` always succeeds (returns true from the low-level
// call perspective).  The spec controls whether the output balance of
// toToken is sufficient via `setOutputAmount()`.
// =============================================================================
contract MockRouter {
    address public lastFromToken;
    address public lastToToken;
    uint256 public lastCallValue;
    uint256 public outputAmount;   // how many toTokens to transfer on swap

    /// @notice Pre-configure how many output tokens this router will produce.
    function setOutputAmount(uint256 amount) external {
        outputAmount = amount;
    }

    /// @notice Called by BeefySwapper via low-level router.call(data).
    ///         We parse the minimal info from calldata to record the trade.
    ///         The real swap logic is NONDET-summarised in the CVL spec.
    fallback(bytes calldata) external returns (bytes memory) {
        // Nothing to do — balance manipulation is handled by the harness
        // helper injectRouterOutput() to keep router logic separate.
        return abi.encode(uint256(0));
    }
}

// =============================================================================
// BeefySwapperHarness — thin wrapper over BeefySwapper that exposes
// internal state for formal verification.
//
// Why a harness?
//   BeefySwapper inherits OwnableUpgradeable (proxy pattern).  Several state
//   variables (oracle, slippage, swapInfo mapping) are public, but the SwapInfo
//   struct contains `bytes data` which cannot be returned as a single value
//   in CVL without decomposing it.  This harness adds fine-grained field
//   getters so CVL rules can assert on individual struct members.
//
// Additions:
//   • getSwapInfoRouter()      — router address for a pair
//   • getSwapInfoAmountIndex() — byte offset where amountIn is written
//   • getSwapInfoMinIndex()    — byte offset where minAmountOut is written
//   • getOracleAddr()          — oracle address (oracle is already public;
//                                this alias avoids CVL type-cast issues)
//   • initializeForVerification() — one-shot init wiring mock oracle
// =============================================================================
contract BeefySwapperHarness is BeefySwapper {

    // ---- One-shot initializer for verification --------------------------------

    /// @notice Initialise with the provided oracle address and slippage value.
    ///         Bypasses the proxy constructor so the prover has a clean entry
    ///         point without modelling the upgradeable proxy.
    function initializeForVerification(address _oracle, uint256 _slippage) external {
        this.initialize(_oracle, _slippage);
    }

    // ---- SwapInfo field getters -----------------------------------------------

    /// @notice Returns the router address configured for the (from, to) pair.
    ///         A zero address means no swap data has been set.
    function getSwapInfoRouter(address from, address to) external view returns (address) {
        return swapInfo[from][to].router;
    }

    /// @notice Returns the raw calldata bytes stored for the (from, to) pair.
    ///         Used in specs that assert setSwapInfo writes the correct data.
    function getSwapInfoData(address from, address to) external view returns (bytes memory) {
        return swapInfo[from][to].data;
    }

    /// @notice Returns the amountIndex field for a pair.
    function getSwapInfoAmountIndex(address from, address to) external view returns (uint256) {
        return swapInfo[from][to].amountIndex;
    }

    /// @notice Returns the minIndex field for a pair.
    function getSwapInfoMinIndex(address from, address to) external view returns (uint256) {
        return swapInfo[from][to].minIndex;
    }

    /// @notice Returns the minAmountSign field for a pair.
    function getSwapInfoMinAmountSign(address from, address to) external view returns (int8) {
        return swapInfo[from][to].minAmountSign;
    }

    // ---- Oracle / slippage getters (aliases for CVL convenience) --------------

    /// @notice Alias for oracle — exposed as a plain address so CVL can compare
    ///         against a linked contract address without an interface cast.
    function getOracleAddr() external view returns (address) {
        return address(oracle);
    }

    /// @notice Current owner — alias for OwnableUpgradeable.owner().
    function currentOwner() external view returns (address) {
        return owner();
    }

    // ---- Test helpers ---------------------------------------------------------

    /// @notice Inject toToken balance into the swapper to simulate router output.
    ///         Call this in harness setup before invoking swap() so the
    ///         slippage check in _swap() sees a non-zero output amount.
    function injectRouterOutput(address toToken, uint256 amount) external {
        MockERC20Swappable(toToken).mint(address(this), amount);
    }

    // ---- CVL2 proxy helpers --------------------------------------------------
    // CVL2 cannot dispatch method calls on address-typed rule parameters.
    // These flat helpers let specs check token balances without chaining.

    /// @notice Balance of `user` in token `token` — avoids token.balanceOf() in CVL2.
    function tokenBalanceOf(address token, address user) external view returns (uint256) {
        return MockERC20Swappable(token).balanceOf(user);
    }

    /// @notice Balance of this swapper contract in token `token`.
    function swapperTokenBalance(address token) external view returns (uint256) {
        return MockERC20Swappable(token).balanceOf(address(this));
    }
}
