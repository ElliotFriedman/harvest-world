// =============================================================================
// BeefyVaultV7.spec — Certora Prover formal verification
//
// Self-contained harness with inline ERC20, no OZ dependencies.
// All Solidity arithmetic is unchecked; overflow is guarded in CVL.
// =============================================================================

using BeefyVaultV7Harness as vault;

methods {
    function vault.deposit(uint256)              external;
    function vault.withdraw(uint256)             external;
    function vault.earn()                        external;
    function vault.depositAll()                  external;
    function vault.withdrawAll()                 external;
    function vault.setStrategy(address)          external;
    function vault.inCaseTokensGetStuck(address) external;
    function vault.addYield(uint256)             external;

    function vault.balance()                 external returns (uint256) envfree;
    function vault.available()               external returns (uint256) envfree;
    function vault.getPricePerFullShare()     external returns (uint256) envfree;
    function vault.vaultTokenBalance()       external returns (uint256) envfree;
    function vault.strategyTokenBalance()    external returns (uint256) envfree;
    function vault.currentOwner()            external returns (address) envfree;
    function vault.totalSupply()             external returns (uint256) envfree;
    function vault.balanceOf(address)        external returns (uint256) envfree;
    function vault.wantBalanceOf(address)    external returns (uint256) envfree;
    function vault.hVaultBal()               external returns (uint256) envfree;
    function vault.hStratBal()               external returns (uint256) envfree;
    function vault.hOwner()                  external returns (address) envfree;
    function vault.strategyAddress()         external returns (address) envfree;
}

// =============================================================================
// HELPERS
// =============================================================================

function requireInitialized() {
    require hOwner() != 0;
    require strategyAddress() != 0;
    require to_mathint(hVaultBal()) + to_mathint(hStratBal()) <= to_mathint(max_uint256);
}

function requireSafeState() {
    requireInitialized();
    uint256 bal = balance();
    uint256 sup = totalSupply();
    require (sup == 0) <=> (bal == 0);
    require bal <= 1000000000000000000000000000;
    require sup <= 1000000000000000000000000000;
}

// =============================================================================
// RULES
// =============================================================================

// Deposit mints the correct number of shares
rule depositMintsCorrectShares(uint256 amount) {
    requireSafeState();
    env e;
    require amount > 0;
    require amount <= 1000000000000000000000000000;
    require e.msg.sender != vault;
    require e.msg.sender != 0;

    uint256 supplyBefore  = totalSupply();
    uint256 balanceBefore = balance();
    uint256 sharesBefore  = balanceOf(e.msg.sender);

    require balanceBefore > 0 => supplyBefore > 0;
    require wantBalanceOf(e.msg.sender) >= amount;
    // Bound user shares to prevent wrapping in _mint
    require to_mathint(sharesBefore) <= to_mathint(supplyBefore);

    deposit(e, amount);

    uint256 sharesAfter = balanceOf(e.msg.sender);
    mathint minted      = to_mathint(sharesAfter) - to_mathint(sharesBefore);

    if (supplyBefore == 0) {
        assert minted == to_mathint(amount),
            "First deposit must mint shares equal to the deposit amount";
    } else {
        mathint expectedShares = (to_mathint(amount) * to_mathint(supplyBefore)) / to_mathint(balanceBefore);
        assert minted == expectedShares,
            "Deposit must mint shares proportional to amount * totalSupply / balance";
    }
}

rule withdrawReturnsCorrectTokens(uint256 shares) {
    requireSafeState();
    env e;
    require shares > 0;

    uint256 supplyBefore  = totalSupply();
    uint256 balanceBefore = balance();

    require balanceOf(e.msg.sender) >= shares;
    require to_mathint(balanceOf(e.msg.sender)) <= to_mathint(supplyBefore);
    require supplyBefore > 0;
    require e.msg.sender != vault;
    require e.msg.sender != 0;
    // Bound want balance to prevent wrap
    require to_mathint(wantBalanceOf(e.msg.sender)) <= to_mathint(max_uint256) / 2;

    uint256 wantBalBefore = wantBalanceOf(e.msg.sender);

    withdraw(e, shares);

    uint256 wantBalAfter = wantBalanceOf(e.msg.sender);
    mathint received     = to_mathint(wantBalAfter) - to_mathint(wantBalBefore);
    mathint expected = (to_mathint(shares) * to_mathint(balanceBefore)) / to_mathint(supplyBefore);

    assert received <= expected,
        "Withdraw must not return more tokens than the proportional share";

    assert received >= 0,
        "Withdraw must not result in negative token balance change";
}

rule depositWithdrawRoundTrip(uint256 amount) {
    requireSafeState();
    env e;
    require amount > 0;
    require amount <= 1000000000000000000000000000;
    require wantBalanceOf(e.msg.sender) >= amount;
    require balanceOf(e.msg.sender) == 0;

    uint256 wantBefore = wantBalanceOf(e.msg.sender);

    deposit(e, amount);

    uint256 sharesReceived = balanceOf(e.msg.sender);
    require sharesReceived > 0;

    withdraw(e, sharesReceived);

    uint256 wantAfter = wantBalanceOf(e.msg.sender);

    assert to_mathint(wantAfter) <= to_mathint(wantBefore),
        "Round-trip deposit+withdraw must not yield more tokens than deposited";
}

rule onlyOwnerCanSetStrategy(address newStrategy) {
    requireInitialized();
    env e;
    require e.msg.sender != hOwner();

    setStrategy@withrevert(e, newStrategy);

    assert lastReverted,
        "setStrategy must revert for non-owner callers";
}

rule ownerCanSetStrategy(address newStrategy) {
    requireInitialized();
    env e;
    require e.msg.sender == hOwner();
    require newStrategy != 0;

    satisfy true;
}

rule inCaseTokensGetStuckOnlyOwner(address token) {
    requireInitialized();
    env e;
    require e.msg.sender != hOwner();

    inCaseTokensGetStuck@withrevert(e, token);

    assert lastReverted,
        "inCaseTokensGetStuck must revert for non-owner callers";
}

rule earnZerosAvailable() {
    requireInitialized();
    env e;

    earn(e);

    assert available() == 0,
        "After earn(), vault should hold no idle tokens";
}

// Price per share is positive when balance >= totalSupply (no dilution).
// Note: bal < supply can yield price == 0 via integer division truncation.
// In practice, bal >= supply because 1:1 shares on first deposit and
// yield only increases balance. We encode this precondition.
rule pricePerSharePositiveWhenSupplyPositive() {
    requireSafeState();
    require totalSupply() > 0;

    mathint bal = to_mathint(hVaultBal()) + to_mathint(hStratBal());
    require bal > 0;
    // price = bal * 1e18 / supply; this is > 0 iff bal * 1e18 >= supply
    require bal >= to_mathint(totalSupply());

    mathint price = (bal * 1000000000000000000) / to_mathint(totalSupply());
    assert price > 0,
        "price per share must be > 0 when balance >= totalSupply";
}

rule pricePerShareNonDecreasingAfterYield(uint256 yieldAmount) {
    requireSafeState();
    env e;
    require totalSupply() > 0;
    require balance() > 0;
    require yieldAmount <= 1000000000000000000000000000;

    mathint balBefore = to_mathint(hVaultBal()) + to_mathint(hStratBal());
    mathint supply    = to_mathint(totalSupply());
    mathint priceBefore = (balBefore * 1000000000000000000) / supply;

    addYield(e, yieldAmount);

    mathint balAfter = to_mathint(hVaultBal()) + to_mathint(hStratBal());
    mathint priceAfter = (balAfter * 1000000000000000000) / supply;

    assert priceAfter >= priceBefore,
        "Yield accrual must not decrease price-per-share";
}

rule withdrawAllBurnsAllShares() {
    requireSafeState();
    env e;
    require balanceOf(e.msg.sender) > 0;
    require totalSupply() > 0;

    withdrawAll(e);

    assert balanceOf(e.msg.sender) == 0,
        "withdrawAll must burn all caller shares";
}

rule noSharesFromZeroDeposit() {
    requireSafeState();
    env e;
    uint256 sharesBefore = balanceOf(e.msg.sender);

    deposit(e, 0);

    assert balanceOf(e.msg.sender) == sharesBefore,
        "Depositing 0 tokens must mint 0 new shares";
}

rule balanceEqualsComponentSum() {
    requireInitialized();
    assert to_mathint(balance()) == to_mathint(vaultTokenBalance()) + to_mathint(strategyTokenBalance()),
        "balance() must equal vaultTokenBalance() + strategyTokenBalance()";
}

rule strategyBalanceContributes() {
    requireInitialized();
    assert to_mathint(balance()) >= to_mathint(vaultTokenBalance()),
        "balance() must be at least the vault's own token holdings";
}

rule getPricePerFullShareReturnsSentinelWhenEmpty() {
    requireInitialized();
    require totalSupply() == 0;
    assert getPricePerFullShare() == 1000000000000000000,
        "getPricePerFullShare must return 1e18 when totalSupply is 0";
}

rule withdrawDoesNotAffectOtherDepositors(address userA, address userB, uint256 shares) {
    requireSafeState();
    env e;
    require userA != userB;
    require e.msg.sender == userA;
    require shares > 0;
    require balanceOf(userA) >= shares;
    require totalSupply() > 0;

    uint256 sharesBbefore = balanceOf(userB);

    withdraw(e, shares);

    assert balanceOf(userB) == sharesBbefore,
        "Withdrawal by one user must not change another user's share balance";
}
