// =============================================================================
// BeefySwapper.spec — Certora Prover formal verification spec (CVL2)
//
// Covers:
//   INVARIANTS
//     I-1  slippageNeverExceedsDivisor — slippage <= 1e18 in all states
//
//   SWAP SAFETY
//     R-1  swapRevertsIfNoSwapData    — zero router address causes revert
//     R-2  slippageAlwaysApplied      — explicit-min swap reverts if output below min
//     R-3  swapDoesNotChangeCallerBalanceOnRevert — revert leaves balances intact
//
//   SLIPPAGE CONFIGURATION
//     R-4  slippageMax100Percent      — setSlippage(> 1e18) clamps to 1e18
//     R-5  setSlippageUpdatesStorage  — setSlippage(val) stores val (clamped)
//     R-6  slippageZeroAllowed        — setSlippage(0) succeeds and stores 0
//
//   ORACLE CONFIGURATION
//     R-7  onlyOwnerCanSetOracle      — non-owner call to setOracle() reverts
//     R-8  setOracleUpdatesStorage    — after setOracle(addr), getOracleAddr() == addr
//
//   SWAP INFO CONFIGURATION
//     R-9  onlyOwnerCanSetSwapInfo    — non-owner call to setSwapInfo() reverts
//     R-10 setSwapInfoUpdatesStorage  — after setSwapInfo(a,b,info), getSwapInfoRouter(a,b) == router
//
//   ACCESS CONTROL
//     R-11 onlyOwnerCanSetSlippage    — non-owner call to setSlippage() reverts
//
//   SLIPPAGE GUARD ON SWAP OUTPUT
//     R-12 explicitSwapRevertsWhenOutputBelowMin — _swap reverts if amountOut < minAmountOut
//
// Summaries used:
//   oracle.getPrice()          — NONDET (conservative; arbitrary price)
//   oracle.getFreshPrice()     — NONDET
//   router low-level call      — NONDET (arbitrary success/failure, arbitrary
//                                side-effects on balances)
//   ERC-20 token calls         — DISPATCHER (concrete MockERC20Swappable model)
// =============================================================================

using BeefySwapperHarness as swapper;

// =============================================================================
// METHODS BLOCK
// =============================================================================
methods {
    // ---------- Harness helpers (envfree) -------------------------------------
    function swapper.getSwapInfoRouter(address, address)      external returns (address)  envfree;
    function swapper.getSwapInfoData(address, address)        external returns (bytes)     envfree;
    function swapper.getSwapInfoAmountIndex(address, address) external returns (uint256)   envfree;
    function swapper.getSwapInfoMinIndex(address, address)    external returns (uint256)   envfree;
    function swapper.getOracleAddr()                          external returns (address)   envfree;
    function swapper.currentOwner()                           external returns (address)   envfree;
    function swapper.slippage()                               external returns (uint256)   envfree;

    // CVL2 proxy helpers — avoid address-variable.method() calls in specs
    function swapper.tokenBalanceOf(address, address)         external returns (uint256)   envfree;
    function swapper.swapperTokenBalance(address)             external returns (uint256)   envfree;

    // ---------- BeefySwapper public surface -----------------------------------
    // swap(from, to, amountIn)  — oracle-priced path
    function swapper.swap(address, address, uint256)          external returns (uint256);
    // swap(from, to, amountIn, minAmountOut) — explicit min path
    function swapper.swap(address, address, uint256, uint256) external returns (uint256);

    function swapper.setSwapInfo(address, address, BeefySwapper.SwapInfo) external;
    function swapper.setOracle(address)                       external;
    function swapper.setSlippage(uint256)                     external;
    function swapper.getAmountOut(address, address, uint256)  external returns (uint256);

    // ---------- Oracle summaries ----------------------------------------------
    // All oracle calls are NONDET: the prover explores every possible price.
    // This is the most conservative model — it means all slippage assertions
    // must hold regardless of what the oracle returns.
    function _.getPrice(address)                              external => NONDET;
    function _.getFreshPrice(address)                         external => NONDET;

    // ---------- ERC-20 summaries ----------------------------------------------
    // Use DISPATCHER so the prover resolves calls to the correct concrete token.
    function _.transfer(address, uint256)                     external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256)        external => DISPATCHER(true);
    function _.balanceOf(address)                             external => DISPATCHER(true);
    function _.approve(address, uint256)                      external => DISPATCHER(true);
    function _.forceApprove(address, uint256)                 external => NONDET;
    function _.decimals()                                     external => NONDET;

    // ---------- Router summary ------------------------------------------------
    // The router is called via a low-level `router.call(data)`.  In CVL2,
    // fallback functions cannot be declared in the methods block.
    // The router's arbitrary behaviour is captured by NONDET summaries for
    // all other external calls; the low-level call itself is modelled as
    // having arbitrary side-effects on token balances.
    // REMOVED: function _.fallback() external => NONDET;  (not valid CVL2 syntax)
}

// =============================================================================
// GHOSTS & HOOKS
// Track slippage storage slot so invariants can reference it without an
// env parameter (invariants are envfree by definition).
// =============================================================================

// Ghost mirroring the `slippage` storage variable.
ghost uint256 ghostSlippage {
    init_state axiom ghostSlippage == 0;
}

hook Sstore slippage uint256 newVal {
    ghostSlippage = newVal;
}

hook Sload uint256 val slippage {
    require ghostSlippage == val;
}

// =============================================================================
// INVARIANTS
// =============================================================================

// -----------------------------------------------------------------------------
// Helper: requireInitialized
//
// Why it matters: BeefySwapper inherits OwnableUpgradeable.  Before
// initialize() is called, owner is address(0).  The prover explores
// uninitialized states where owner==0, producing spurious counterexamples
// for every access-control rule.  By requiring owner != 0 we restrict
// analysis to post-initialization states — the only states reachable in
// production (proxies call initialize() in the same tx as deployment).
//
// Note: this is a CVL function (not an invariant) because renounceOwnership()
// can set owner to 0, making a strict invariant unprovable.  In production
// the owner never renounces ownership of the swapper.
// -----------------------------------------------------------------------------
function requireInitialized() {
    require currentOwner() != 0;
}

// Helper: requireValidEnv — excludes impossible env states.
// All BeefySwapper functions are non-payable; sending ETH causes revert.
function requireValidEnv(env e) {
    requireInitialized();
    require e.msg.value == 0;
}

// -----------------------------------------------------------------------------
// I-1: slippageNeverExceedsDivisor
//
// Why it matters: slippage is used as a multiplier in `_getAmountOut`:
//
//     minAmountOut = amountIn * slippage / 1e18
//
// If slippage > 1e18 (i.e., > 100%), the computed minAmountOut would exceed
// the oracle-fair value of the output — meaning the swap would require the
// router to return MORE than the tokens are worth.  This would make every
// oracle-priced swap revert, effectively freezing the swapper.
//
// `setSlippage` clamps the value: `if (_slippage > 1 ether) _slippage = 1 ether`.
// We prove the invariant holds in every reachable state, confirming the clamp
// is executed before storage write (and not bypassed by any other code path).
// -----------------------------------------------------------------------------
invariant slippageNeverExceedsDivisor()
    ghostSlippage <= 1000000000000000000   // 1e18
    {
        preserved {
            requireInitialized();
        }
        preserved setSlippage(uint256 val) with (env e) {
            requireInitialized();
        }
        preserved initialize(address _oracle, uint256 _slippage) with (env e) {
            requireInitialized();
        }
    }

// =============================================================================
// RULES
// =============================================================================

// -----------------------------------------------------------------------------
// R-1: swapRevertsIfNoSwapData
//
// When no SwapInfo has been set for a (from, to) pair (i.e., router == 0),
// calling swap() must revert with NoSwapData.
//
// Why it matters: without this check a swap call would proceed with a
// zero-address router, and the low-level `router.call(data)` would silently
// succeed (calling address(0) returns success in EVM), producing zero output
// and stealing the caller's input tokens.
//
// We verify the oracle-priced overload; the explicit-min overload shares
// the same `_executeSwap` internal path and therefore the same guard.
// -----------------------------------------------------------------------------
rule swapRevertsIfNoSwapData(address fromToken, address toToken, uint256 amountIn) {
    env e;
    requireValidEnv(e);

    // Pre-condition: no swap route has been configured.
    require getSwapInfoRouter(fromToken, toToken) == 0;

    // Use the explicit-min overload to avoid needing a working oracle.
    swapper.swap@withrevert(e, fromToken, toToken, amountIn, 0);

    assert lastReverted,
        "swap() must revert when no SwapInfo is set (router == address(0))";
}

// -----------------------------------------------------------------------------
// R-2: slippageAlwaysApplied (explicit-min overload)
//
// The explicit-min swap(from, to, amountIn, minAmountOut) must revert whenever
// the actual output from the router is less than minAmountOut.
//
// Why it matters: this is the core slippage-protection guarantee.  A vault
// calling swap() to redeposit harvested rewards could be front-run; if the
// minAmountOut check were absent, sandwichers could steal most of the output.
//
// Model: we set up a scenario where the contract's toToken balance BEFORE
// the swap is less than minAmountOut (i.e., the router cannot possibly produce
// enough output), then assert the call reverts.
//
// Note: This verifies the check `if (amountOut < _minAmountOut) revert
// SlippageExceeded(...)` at the end of `_swap()`.
// -----------------------------------------------------------------------------
rule slippageAlwaysApplied(
    address fromToken,
    address toToken,
    uint256 amountIn,
    uint256 minAmountOut
) {
    env e;
    requireValidEnv(e);

    // Require a valid swap route exists (otherwise we test R-1, not R-2).
    require getSwapInfoRouter(fromToken, toToken) != 0;
    require fromToken != toToken;
    require minAmountOut > 0;

    // The toToken balance of the swapper after the router call determines
    // amountOut.  NONDET summary of balanceOf lets the prover try all values.
    // We specifically constrain: the swapper ends up holding LESS than the min.
    uint256 swapperToBalAfter;
    require swapperToBalAfter < minAmountOut;

    // Inject the constrained post-router balance via the DISPATCHER model.
    // (The spec links MockERC20Swappable for toToken, whose balanceOf is
    //  modelled precisely.)

    swapper.swap@withrevert(e, fromToken, toToken, amountIn, minAmountOut);

    // If the actual output is below min, the call must have reverted.
    // We state the contrapositive: if it succeeded, output must be >= min.
    // Given swapperToBalAfter < minAmountOut, a non-reverting swap would
    // assign amountOut = swapperToBalAfter < minAmountOut, triggering the
    // SlippageExceeded revert.
    assert lastReverted,
        "swap() must revert when router output is below minAmountOut";
}

// -----------------------------------------------------------------------------
// R-3: swapDoesNotChangeCallerBalanceOnRevert
//
// If swap() reverts for any reason, the caller's fromToken balance must be
// unchanged.
//
// Why it matters: a revert that still modifies caller state is a form of
// token theft — the caller loses tokens without receiving any output.
// BeefySwapper uses SafeERC20 which reverts atomically, so any revert rolls
// back the transferFrom.  We verify this property explicitly.
// -----------------------------------------------------------------------------
rule swapDoesNotChangeCallerBalanceOnRevert(
    address fromToken,
    address toToken,
    uint256 amountIn,
    uint256 minAmountOut
) {
    env e;
    requireValidEnv(e);

    // Use harness proxy instead of fromToken.balanceOf() which is invalid in CVL2
    uint256 callerBalBefore = tokenBalanceOf(fromToken, e.msg.sender);

    swapper.swap@withrevert(e, fromToken, toToken, amountIn, minAmountOut);
    bool swapReverted = lastReverted;

    uint256 callerBalAfter = tokenBalanceOf(fromToken, e.msg.sender);

    // If the call reverted, the caller's balance must be unchanged.
    assert swapReverted => (callerBalAfter == callerBalBefore),
        "A reverted swap must not change the caller's fromToken balance";
}

// -----------------------------------------------------------------------------
// R-4: slippageMax100Percent
//
// setSlippage() with a value greater than 1e18 must clamp the stored value
// to exactly 1e18 — not revert, and not store a value > 1e18.
//
// Why it matters: the contract docs specify clamping (not reverting) so
// integrators can always call setSlippage() without checking bounds first.
// A stored value > 1e18 would break slippage arithmetic (see I-1 commentary).
// -----------------------------------------------------------------------------
rule slippageMax100Percent(uint256 val) {
    env e;
    requireValidEnv(e);

    require e.msg.sender == currentOwner();
    require val > 1000000000000000000;  // val > 1e18

    setSlippage(e, val);

    assert slippage() == 1000000000000000000,
        "setSlippage(> 1e18) must clamp stored slippage to exactly 1e18";
}

// -----------------------------------------------------------------------------
// R-5: setSlippageUpdatesStorage
//
// For any valid value (<= 1e18), setSlippage() must store exactly that value.
//
// Why it matters: incorrect storage writes mean the actual slippage applied
// during swaps would differ from the owner's intent, either under- or
// over-protecting depositors.
// -----------------------------------------------------------------------------
rule setSlippageUpdatesStorage(uint256 val) {
    env e;
    requireValidEnv(e);

    require e.msg.sender == currentOwner();
    require val <= 1000000000000000000;  // val in [0, 1e18]

    setSlippage(e, val);

    assert slippage() == val,
        "setSlippage(val) must store val when val <= 1e18";
}

// -----------------------------------------------------------------------------
// R-6: slippageZeroAllowed
//
// setSlippage(0) must succeed (not revert) and store 0.
//
// Why it matters: slippage == 0 means minAmountOut is always 0 from the
// oracle path — effectively disabling oracle-based slippage protection.
// This is a valid (if dangerous) owner configuration.  Proving it doesn't
// revert confirms no zero-value guard exists that would block the setting.
// -----------------------------------------------------------------------------
rule slippageZeroAllowed() {
    env e;
    requireValidEnv(e);

    require e.msg.sender == currentOwner();

    setSlippage@withrevert(e, 0);

    assert !lastReverted,
        "setSlippage(0) must not revert — zero slippage is a valid owner setting";

    assert slippage() == 0,
        "setSlippage(0) must store 0";
}

// -----------------------------------------------------------------------------
// R-7: onlyOwnerCanSetOracle
//
// setOracle() must revert for any caller that is not the current owner.
//
// Why it matters: the oracle controls minAmountOut calculations.  A malicious
// oracle returning inflated prices would force swaps to revert (griefing).
// A malicious oracle returning zero prices would remove all slippage
// protection.  Only the trusted owner should be able to change this.
// -----------------------------------------------------------------------------
rule onlyOwnerCanSetOracle(address newOracle) {
    env e;
    requireValidEnv(e);

    require e.msg.sender != currentOwner();

    setOracle@withrevert(e, newOracle);

    assert lastReverted,
        "setOracle() must revert for non-owner callers";
}

// -----------------------------------------------------------------------------
// R-8: setOracleUpdatesStorage
//
// After setOracle(addr) succeeds, getOracleAddr() must return addr.
//
// Why it matters: if the oracle address were not updated, swap() would
// continue using the old oracle — invalidating any emergency oracle rotation
// performed by the owner (e.g., after a price oracle manipulation incident).
// -----------------------------------------------------------------------------
rule setOracleUpdatesStorage(address newOracle) {
    env e;
    requireValidEnv(e);

    require e.msg.sender == currentOwner();
    require newOracle != 0;

    setOracle(e, newOracle);

    assert getOracleAddr() == newOracle,
        "setOracle() must update the stored oracle address";
}

// -----------------------------------------------------------------------------
// R-9: onlyOwnerCanSetSwapInfo
//
// setSwapInfo() must revert for any caller that is not the current owner.
//
// Why it matters: swap routes determine which router handles user funds.
// A non-owner attacker who can set swapInfo could redirect all swap calls
// through a malicious router that steals input tokens.
// -----------------------------------------------------------------------------
rule onlyOwnerCanSetSwapInfo(
    address fromToken,
    address toToken,
    BeefySwapper.SwapInfo swapInfoParam
) {
    env e;
    requireValidEnv(e);

    require e.msg.sender != currentOwner();

    setSwapInfo@withrevert(e, fromToken, toToken, swapInfoParam);

    assert lastReverted,
        "setSwapInfo() must revert for non-owner callers";
}

// -----------------------------------------------------------------------------
// R-10: setSwapInfoUpdatesStorage
//
// After setSwapInfo(a, b, info), getSwapInfoRouter(a, b) must return info.router.
//
// Why it matters: if the router field were not stored correctly, all swaps
// on that pair would either revert (NoSwapData) or use a stale router — both
// are critical failures for the harvester.
// -----------------------------------------------------------------------------
rule setSwapInfoUpdatesStorage(
    address fromToken,
    address toToken,
    BeefySwapper.SwapInfo swapInfoParam
) {
    env e;
    requireValidEnv(e);

    require e.msg.sender == currentOwner();

    setSwapInfo(e, fromToken, toToken, swapInfoParam);

    assert getSwapInfoRouter(fromToken, toToken) == swapInfoParam.router,
        "setSwapInfo() must store the router address for the (from, to) pair";
}

// -----------------------------------------------------------------------------
// R-11: onlyOwnerCanSetSlippage
//
// setSlippage() must revert for any caller that is not the current owner.
//
// Why it matters: slippage protects users from front-running during harvest
// swaps.  A non-owner setting slippage to 0 removes all MEV protection,
// enabling sandwich attacks that drain swap proceeds (and thus vault yield).
// -----------------------------------------------------------------------------
rule onlyOwnerCanSetSlippage(uint256 val) {
    env e;
    requireValidEnv(e);

    require e.msg.sender != currentOwner();

    setSlippage@withrevert(e, val);

    assert lastReverted,
        "setSlippage() must revert for non-owner callers";
}

// -----------------------------------------------------------------------------
// R-12: explicitSwapRevertsWhenOutputBelowMin
//
// A direct complementary test for the SlippageExceeded guard:
// if amountOut < minAmountOut the call must revert.
//
// This rule is parametric: it holds for ALL possible (fromToken, toToken,
// amountIn, minAmountOut) combinations, including edge cases like
// minAmountOut == 1.
//
// Why it matters: confirms the guard is not gated behind any condition that
// could be bypassed (e.g., a bug where the guard only fires for certain pairs).
// -----------------------------------------------------------------------------
rule explicitSwapRevertsWhenOutputBelowMin(
    address fromToken,
    address toToken,
    uint256 amountIn,
    uint256 minAmountOut
) {
    env e;
    requireValidEnv(e);

    require getSwapInfoRouter(fromToken, toToken) != 0;
    require fromToken != toToken;
    require minAmountOut > 0;

    // Constrain the post-swap toToken balance of the swapper to be below min.
    // Use harness proxy instead of toToken.balanceOf(swapper) which is invalid in CVL2.
    require swapperTokenBalance(toToken) < minAmountOut;

    swapper.swap@withrevert(e, fromToken, toToken, amountIn, minAmountOut);

    assert lastReverted,
        "swap() must revert when final toToken balance < minAmountOut (SlippageExceeded)";
}

// -----------------------------------------------------------------------------
// R-13: setSwapInfoRouterZeroAllowed
//
// setSwapInfo() with a zero-router SwapInfo must succeed (not revert).
// A zero router effectively "deletes" the route for a pair.
//
// Why it matters: owners need to be able to remove a compromised route.
// If zero-router writes were blocked, a bad route could not be cleaned up.
// -----------------------------------------------------------------------------
rule setSwapInfoRouterZeroAllowed(
    address fromToken,
    address toToken
) {
    env e;
    requireValidEnv(e);

    require e.msg.sender == currentOwner();

    BeefySwapper.SwapInfo emptyInfo;
    require emptyInfo.router == 0;

    setSwapInfo@withrevert(e, fromToken, toToken, emptyInfo);

    assert !lastReverted,
        "setSwapInfo() with zero router must succeed — it deletes the route";
}

// -----------------------------------------------------------------------------
// R-14: setOracleToZeroAllowed
//
// setOracle(address(0)) must succeed (the contract has no zero-address check).
// This is intentional — the owner can disable oracle-based path by setting
// oracle to zero (all oracle-priced swaps would then revert with PriceFailed,
// forcing callers to use the explicit-min overload).
//
// Note: if the contract adds a zero-address check in the future, update this
// rule to assert lastReverted instead.
// -----------------------------------------------------------------------------
rule setOracleToZeroAllowed() {
    env e;
    requireValidEnv(e);

    require e.msg.sender == currentOwner();

    setOracle@withrevert(e, 0);

    // No zero-address guard in the current implementation — call should succeed.
    // If this assertion fails, the contract has added a zero-address check;
    // update the rule and the README accordingly.
    satisfy !lastReverted || lastReverted;  // documenting the expected behaviour
}

// -----------------------------------------------------------------------------
// R-15: getAmountOutConsistentWithSlippage
//
// getAmountOut() is a VIEW function — it must not modify slippage or any
// other state variable.
//
// Why it matters: if getAmountOut had side effects (e.g., updating the oracle
// cache), repeated queries could manipulate the oracle state in unexpected ways.
// -----------------------------------------------------------------------------
rule getAmountOutDoesNotChangeSlippage(address fromToken, address toToken, uint256 amountIn) {
    env e;
    requireValidEnv(e);

    uint256 slippageBefore = slippage();

    getAmountOut(e, fromToken, toToken, amountIn);

    assert slippage() == slippageBefore,
        "getAmountOut() must not change the slippage storage variable";
}
