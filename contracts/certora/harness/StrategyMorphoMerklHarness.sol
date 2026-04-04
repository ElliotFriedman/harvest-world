// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ============================================================================
// Self-contained Certora harness for StrategyMorphoMerkl.
//
// No OZ dependencies. Reimplements the strategy logic inline so the Certora
// prover (CLI 6.3.1) can resolve all function pointers without encountering
// "EVM instruction jumps to unknown destination" errors from OZ's Initializable,
// OwnableUpgradeable, PausableUpgradeable, and SafeERC20.
// ============================================================================

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC4626 is IERC20 {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function deposit(uint256, address) external returns (uint256);
    function withdraw(uint256, address, address) external returns (uint256);
    function redeem(uint256, address, address) external returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(address) external view returns (uint256);
    function maxRedeem(address) external view returns (uint256);
    function previewDeposit(uint256) external view returns (uint256);
    function previewMint(uint256) external view returns (uint256);
    function previewWithdraw(uint256) external view returns (uint256);
    function previewRedeem(uint256) external view returns (uint256);
    function mint(uint256, address) external returns (uint256);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
}

interface IMerklClaimer {
    function claim(address[] calldata, address[] calldata, uint256[] calldata, bytes32[][] calldata) external;
}

// =============================================================================
// MockERC20Simple
// =============================================================================
contract MockERC20Simple is IERC20 {
    string  public name;
    string  public symbol;
    uint8   public decimals;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _dec) {
        name = _name; symbol = _symbol; decimals = _dec;
    }
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view override returns (uint256) { return _balances[a]; }
    function transfer(address to, uint256 amt) external override returns (bool) {
        require(_balances[msg.sender] >= amt, "insufficient");
        _balances[msg.sender] -= amt; _balances[to] += amt;
        emit Transfer(msg.sender, to, amt); return true;
    }
    function allowance(address o, address s) external view override returns (uint256) { return _allowances[o][s]; }
    function approve(address s, uint256 amt) external override returns (bool) {
        _allowances[msg.sender][s] = amt; emit Approval(msg.sender, s, amt); return true;
    }
    function transferFrom(address from, address to, uint256 amt) external override returns (bool) {
        uint256 a = _allowances[from][msg.sender];
        if (a != type(uint256).max) { require(a >= amt, "allowance"); _allowances[from][msg.sender] = a - amt; }
        require(_balances[from] >= amt, "balance");
        _balances[from] -= amt; _balances[to] += amt;
        emit Transfer(from, to, amt); return true;
    }
    function forceApprove(address s, uint256 amt) external {
        _allowances[msg.sender][s] = amt; emit Approval(msg.sender, s, amt);
    }
    function mint(address to, uint256 amt) external {
        _balances[to] += amt; _totalSupply += amt; emit Transfer(address(0), to, amt);
    }
    function burn(address from, uint256 amt) external {
        require(_balances[from] >= amt, "burn");
        _balances[from] -= amt; _totalSupply -= amt; emit Transfer(from, address(0), amt);
    }
}

// =============================================================================
// MockMorphoVault
// =============================================================================
contract MockMorphoVault is IERC4626 {
    IERC20 public immutable _asset;
    mapping(address => uint256) private _shares;
    uint256 private _totalShares;
    uint256 private _totalAssets;

    constructor(address assetToken) { _asset = IERC20(assetToken); }

    function asset() external view override returns (address) { return address(_asset); }
    function totalAssets() external view override returns (uint256) { return _totalAssets; }
    function totalSupply() external view override returns (uint256) { return _totalShares; }
    function balanceOf(address a) external view override returns (uint256) { return _shares[a]; }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        if (_totalShares == 0 || _totalAssets == 0) return assets;
        return assets * _totalShares / _totalAssets;
    }
    function convertToAssets(uint256 shares) external view override returns (uint256) {
        if (_totalShares == 0) return 0;
        return shares * _totalAssets / _totalShares;
    }
    function maxDeposit(address) external pure override returns (uint256) { return type(uint256).max; }
    function maxMint(address) external pure override returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address o) external view override returns (uint256) {
        return _shares[o] * _totalAssets / (_totalShares == 0 ? 1 : _totalShares);
    }
    function maxRedeem(address o) external view override returns (uint256) { return _shares[o]; }
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

    function deposit(uint256 assets, address receiver) external override returns (uint256 sharesOut) {
        _asset.transferFrom(msg.sender, address(this), assets);
        sharesOut = (_totalShares == 0 || _totalAssets == 0) ? assets : assets * _totalShares / _totalAssets;
        _shares[receiver] += sharesOut; _totalShares += sharesOut; _totalAssets += assets;
        emit Deposit(msg.sender, receiver, assets, sharesOut);
    }
    function mint(uint256 shares, address receiver) external override returns (uint256 assetsIn) {
        assetsIn = (_totalShares == 0) ? shares : shares * _totalAssets / _totalShares;
        _asset.transferFrom(msg.sender, address(this), assetsIn);
        _shares[receiver] += shares; _totalShares += shares; _totalAssets += assetsIn;
        emit Deposit(msg.sender, receiver, assetsIn, shares);
    }
    function withdraw(uint256 assets, address receiver, address owner_) external override returns (uint256 sharesIn) {
        require(_totalAssets > 0, "empty");
        sharesIn = assets * _totalShares / _totalAssets;
        require(_shares[owner_] >= sharesIn, "shares");
        _shares[owner_] -= sharesIn; _totalShares -= sharesIn; _totalAssets -= assets;
        _asset.transfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner_, assets, sharesIn);
    }
    function redeem(uint256 shares, address receiver, address owner_) external override returns (uint256 assetsOut) {
        require(_shares[owner_] >= shares, "shares");
        assetsOut = (_totalShares == 0) ? 0 : shares * _totalAssets / _totalShares;
        _shares[owner_] -= shares; _totalShares -= shares; _totalAssets -= assetsOut;
        _asset.transfer(receiver, assetsOut);
        emit Withdraw(msg.sender, receiver, owner_, assetsOut, shares);
    }
    function transfer(address to, uint256 amt) external override returns (bool) {
        require(_shares[msg.sender] >= amt); _shares[msg.sender] -= amt; _shares[to] += amt;
        emit Transfer(msg.sender, to, amt); return true;
    }
    function allowance(address, address) external pure override returns (uint256) { return 0; }
    function approve(address s, uint256 amt) external override returns (bool) {
        emit Approval(msg.sender, s, amt); return true;
    }
    function transferFrom(address from, address to, uint256 amt) external override returns (bool) {
        require(_shares[from] >= amt); _shares[from] -= amt; _shares[to] += amt;
        emit Transfer(from, to, amt); return true;
    }

    // Test helpers
    function addYield(uint256 yieldAmount) external { _totalAssets += yieldAmount; }
    function sharesOf(address a) external view returns (uint256) { return _shares[a]; }
}

// =============================================================================
// MockBeefySwapper
// =============================================================================
contract MockBeefySwapper {
    function swap(address, address, uint256 amountIn) external pure returns (uint256) { return amountIn; }
    function swap(address, address, uint256 amountIn, uint256) external pure returns (uint256) { return amountIn; }
    function getAmountOut(address, address, uint256 amountIn) external pure returns (uint256) { return amountIn; }
}

// =============================================================================
// MockMerklClaimer
// =============================================================================
contract MockMerklClaimer is IMerklClaimer {
    address public lastCalledClaimer;
    address[] public lastUsers;
    address[] public lastTokens;
    uint256 public claimCallCount;

    function claim(
        address[] calldata users, address[] calldata tokens,
        uint256[] calldata, bytes32[][] calldata
    ) external override {
        lastCalledClaimer = address(this);
        claimCallCount += 1;
        if (users.length > 0) lastUsers = users;
        if (tokens.length > 0) lastTokens = tokens;
    }
}

// =============================================================================
// StrategyMorphoMerklHarness — self-contained, no OZ
//
// Reimplements the full strategy logic from BaseAllToNativeFactoryStrat +
// StrategyMorphoMerkl without OZ imports.  Every storage slot and function
// mirrors the original contracts.
// =============================================================================
contract StrategyMorphoMerklHarness {

    // ---- Storage (mirrors BaseAllToNativeFactoryStrat) ----------------------
    address public want;
    address public depositToken;
    address public vault;
    address public swapper;
    address public strategist;
    address public feeRecipient;

    address[] public rewards;
    mapping(address => uint256) public minAmounts;

    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;
    bool    public harvestOnDeposit;

    address private _owner;
    bool    private _paused;

    // ---- Storage (mirrors StrategyMorphoMerkl) -----------------------------
    IERC4626      public morphoVault;
    IMerklClaimer public claimer;

    // WETH on World Chain
    address public constant NATIVE = 0x4200000000000000000000000000000000000006;
    uint256 public constant HARVEST_FEE = 0;
    uint256 constant DIVISOR = 1 ether;

    // ---- Events ------------------------------------------------------------
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 feeAmount);

    // ---- Access control (inline, no OZ) ------------------------------------
    function owner() public view returns (address) { return _owner; }
    function currentOwner() external view returns (address) { return _owner; }
    function paused() public view returns (bool) { return _paused; }

    modifier onlyManager() { require(msg.sender == _owner, "!manager"); _; }
    modifier onlyOwner()   { require(msg.sender == _owner, "!owner"); _; }
    modifier ifNotPaused() { require(!_paused, "paused"); _; }

    // ---- Initialize (inline, no OZ Initializable) --------------------------
    bool private _initialized;

    struct Addresses {
        address want;
        address depositToken;
        address vault;
        address swapper;
        address strategist;
        address feeRecipient;
    }

    function initialize(
        address _morphoVault,
        address _claimer,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public {
        require(!_initialized, "already initialized");
        _initialized = true;
        _owner = msg.sender;
        want = _addresses.want;
        vault = _addresses.vault;
        swapper = _addresses.swapper;
        strategist = _addresses.strategist;
        feeRecipient = _addresses.feeRecipient;
        morphoVault = IERC4626(_morphoVault);
        claimer = IMerklClaimer(_claimer);
        lockDuration = 1 days;
        for (uint256 i; i < _rewards.length; i++) {
            _addRewardUnchecked(_rewards[i]);
        }
        if (_harvestOnDeposit) {
            harvestOnDeposit = true;
            lockDuration = 0;
        }
    }

    function initializeForVerification(
        address _morphoVault, address _claimer, address _want,
        address _swapper, address _vault, address _strategist,
        address _feeRecipient, address[] calldata _rewards
    ) external {
        Addresses memory addrs = Addresses(_want, address(0), _vault, _swapper, _strategist, _feeRecipient);
        this.initialize(_morphoVault, _claimer, false, _rewards, addrs);
    }

    // ---- Core strategy logic (from BaseAllToNativeFactoryStrat) -------------

    function balanceOfPool() public view returns (uint256) {
        return morphoVault.convertToAssets(morphoVault.balanceOf(address(this)));
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function lockedProfit() public view returns (uint256) {
        if (lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < lockDuration ? lockDuration - elapsed : 0;
        return totalLocked * remaining / lockDuration;
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    function deposit() public ifNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            IERC20(want).approve(address(morphoVault), wantBal);
            morphoVault.deposit(wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amount) {
            morphoVault.withdraw(_amount - wantBal, address(this), address(this));
            wantBal = balanceOfWant();
        }
        if (wantBal > _amount) { wantBal = _amount; }
        IERC20(want).transfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _emergencyWithdraw();
        IERC20(want).transfer(vault, balanceOfWant());
    }

    function panic() public onlyManager {
        _paused = true;
        _emergencyWithdraw();
    }

    function pause() public onlyManager { _paused = true; }

    function unpause() external onlyManager {
        _paused = false;
        deposit();
    }

    function _emergencyWithdraw() internal {
        uint256 bal = morphoVault.balanceOf(address(this));
        if (bal > 0) {
            morphoVault.redeem(bal, address(this), address(this));
        }
    }

    // ---- Harvest (from BaseAllToNativeFactoryStrat._harvest) ----------------

    function harvest() external onlyManager { _harvest(false); }
    function harvest(address) external onlyManager { _harvest(false); }

    function _harvest(bool onDeposit) internal ifNotPaused {
        uint256 beforeBal = balanceOfWant();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20(NATIVE).balanceOf(address(this));
        if (nativeBal > minAmounts[NATIVE]) {
            _chargeFees();
            _swapNativeToWant();
            uint256 wantHarvested = balanceOfWant() - beforeBal;
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;
            if (!onDeposit) { deposit(); }
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewardsToNative() internal {
        for (uint256 i; i < rewards.length; ++i) {
            address token = rewards[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > minAmounts[token]) {
                _swap(token, NATIVE, amount);
            }
        }
    }

    function _chargeFees() internal {
        uint256 nativeBal = IERC20(NATIVE).balanceOf(address(this));
        uint256 feeAmount = nativeBal * HARVEST_FEE / DIVISOR;
        if (feeAmount > 0) {
            IERC20(NATIVE).transfer(feeRecipient, feeAmount);
        }
    }

    function _swapNativeToWant() internal {
        if (depositToken == address(0)) {
            uint256 bal = IERC20(NATIVE).balanceOf(address(this));
            _swap(NATIVE, want, bal);
        } else {
            if (depositToken != NATIVE) {
                uint256 bal = IERC20(NATIVE).balanceOf(address(this));
                _swap(NATIVE, depositToken, bal);
            }
            uint256 bal2 = IERC20(depositToken).balanceOf(address(this));
            _swap(depositToken, want, bal2);
        }
    }

    function _swap(address tokenFrom, address tokenTo, uint256 amount) internal {
        if (amount > 0 && tokenFrom != tokenTo) {
            IERC20(tokenFrom).approve(swapper, amount);
            MockBeefySwapper(swapper).swap(tokenFrom, tokenTo, amount, 0);
        }
    }

    // ---- beforeDeposit (harvestOnDeposit gate) ------------------------------

    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(true);
        }
    }

    // ---- Reward management -------------------------------------------------

    function addReward(address _token) public onlyManager {
        require(_token != want, "!want");
        require(_token != NATIVE, "!native");
        require(_token != address(morphoVault), "!morphoVault");
        rewards.push(_token);
    }

    function _addRewardUnchecked(address _token) internal { rewards.push(_token); }

    function addWantAsReward() external onlyOwner { rewards.push(want); }

    function removeReward(uint256 i) external onlyManager {
        rewards[i] = rewards[rewards.length - 1]; rewards.pop();
    }

    function resetRewards() external onlyManager { delete rewards; }

    function setRewardMinAmount(address token, uint256 minAmount) external onlyManager {
        minAmounts[token] = minAmount;
    }

    function rewardsLength() external view returns (uint256) { return rewards.length; }

    // ---- Merkl claim (from StrategyMorphoMerkl) ----------------------------

    function claim(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external {
        address[] memory users = new address[](1);
        users[0] = address(this);
        claimer.claim(users, _tokens, _amounts, _proofs);
    }

    // Base claim() — no-op for Morpho strategy
    function claim() external onlyManager {}

    // ---- Setters -----------------------------------------------------------

    function setClaimer(address _claimer) external onlyManager {
        claimer = IMerklClaimer(_claimer);
    }

    function setVault(address _vault) external onlyOwner { vault = _vault; }
    function setSwapper(address _swapper) external onlyOwner { swapper = _swapper; }
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist"); strategist = _strategist;
    }
    function setFeeRecipient(address _feeRecipient) external onlyOwner { feeRecipient = _feeRecipient; }

    function setDepositToken(address token) public onlyManager {
        if (token == address(0)) { depositToken = address(0); return; }
        require(token != want, "!want");
        require(token != address(morphoVault), "!morphoVault");
        depositToken = token;
    }

    function setHarvestOnDeposit(bool _hod) public onlyManager {
        harvestOnDeposit = _hod;
        lockDuration = _hod ? 0 : 1 days;
    }

    function setLockDuration(uint256 _duration) external onlyManager { lockDuration = _duration; }

    function transferOwnership(address newOwner) external onlyOwner { _owner = newOwner; }
    function renounceOwnership() external onlyOwner { _owner = address(0); }

    // ---- View stubs --------------------------------------------------------
    function stratName() public pure returns (string memory) { return "MorphoMerkl"; }
    function rewardsAvailable() external pure returns (uint256) { return 0; }
    function callReward() external pure returns (uint256) { return 0; }
    function depositFee() public pure returns (uint256) { return 0; }
    function withdrawFee() public pure returns (uint256) { return 0; }

    // ---- Harness helpers (for spec) ----------------------------------------

    function getTotalLocked() external view returns (uint256) { return totalLocked; }
    function getLockDuration() external view returns (uint256) { return lockDuration; }
    function getLastHarvest() external view returns (uint256) { return lastHarvest; }

    function morphoSharesHeld() external view returns (uint256) {
        return morphoVault.balanceOf(address(this));
    }

    function addYieldToMorpho(uint256 yieldAmount) external {
        MockMorphoVault(address(morphoVault)).addYield(yieldAmount);
    }

    function injectRewardTokens(address rewardToken, uint256 amount) external {
        MockERC20Simple(rewardToken).mint(address(this), amount);
    }

    function claimCallCount() external view returns (uint256) {
        return MockMerklClaimer(address(claimer)).claimCallCount();
    }

    function claimerAddress() external view returns (address) { return address(claimer); }
    function currentLockedProfit() external view returns (uint256) { return lockedProfit(); }

    receive() external payable {}
}
