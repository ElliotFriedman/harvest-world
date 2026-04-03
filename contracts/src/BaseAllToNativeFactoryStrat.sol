// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBeefySwapper} from "./interfaces/IBeefySwapper.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";

abstract contract BaseAllToNativeFactoryStrat is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    struct Addresses {
        address want;
        address depositToken;
        address vault;
        address swapper;
        address strategist;
        address feeRecipient;
    }

    // WETH on World Chain (chain ID 480)
    address public constant NATIVE = 0x4200000000000000000000000000000000000006;

    // 0% performance fee for hackathon — all harvested yield goes to depositors
    uint256 public constant HARVEST_FEE = 0;

    uint256 constant DIVISOR = 1 ether;

    address[] public rewards;
    mapping(address => uint256) public minAmounts; // tokens minimum amount to be swapped

    address public vault;
    address public swapper;
    address public strategist;
    address public feeRecipient;

    address public want;
    address public depositToken;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;
    bool public harvestOnDeposit;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 feeAmount);
    event SetVault(address vault);
    event SetSwapper(address swapper);
    event SetStrategist(address strategist);

    error StrategyPaused();
    error NotManager();

    modifier ifNotPaused() {
        if (paused()) revert StrategyPaused();
        _;
    }

    modifier onlyManager() {
        _checkManager();
        _;
    }

    function _checkManager() internal view {
        if (msg.sender != owner()) revert NotManager();
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function __BaseStrategy_init(Addresses memory _addresses, address[] memory _rewards) internal onlyInitializing {
        __Ownable_init();
        __Pausable_init();
        want = _addresses.want;
        vault = _addresses.vault;
        swapper = _addresses.swapper;
        strategist = _addresses.strategist;
        feeRecipient = _addresses.feeRecipient;

        for (uint256 i; i < _rewards.length; i++) {
            addReward(_rewards[i]);
        }
        setDepositToken(_addresses.depositToken);

        lockDuration = 1 days;
    }

    function stratName() public view virtual returns (string memory);

    function balanceOfPool() public view virtual returns (uint256);

    function _deposit(uint256 amount) internal virtual;

    function _withdraw(uint256 amount) internal virtual;

    function _emergencyWithdraw() internal virtual;

    function _claim() internal virtual;

    function _verifyRewardToken(address token) internal view virtual;

    // puts the funds to work
    function deposit() public ifNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            _deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    function claim() external virtual {
        _claim();
    }

    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient, false);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient, bool onDeposit) internal ifNotPaused {
        uint256 beforeBal = balanceOfWant();
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20(NATIVE).balanceOf(address(this));
        if (nativeBal > minAmounts[NATIVE]) {
            _chargeFees(callFeeRecipient);

            _swapNativeToWant();
            uint256 wantHarvested = balanceOfWant() - beforeBal;
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;

            if (!onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewardsToNative() internal virtual {
        for (uint256 i; i < rewards.length; ++i) {
            address token = rewards[i];
            if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                IWrappedNative(NATIVE).deposit{value: address(this).balance}();
            } else {
                uint256 amount = IERC20(token).balanceOf(address(this));
                if (amount > minAmounts[token]) {
                    _swap(token, NATIVE, amount);
                }
            }
        }
    }

    // 5% performance fee sent to feeRecipient
    function _chargeFees(address /*callFeeRecipient*/) internal {
        uint256 nativeBal = IERC20(NATIVE).balanceOf(address(this));
        uint256 feeAmount = nativeBal * HARVEST_FEE / DIVISOR;
        if (feeAmount > 0) {
            IERC20(NATIVE).safeTransfer(feeRecipient, feeAmount);
            emit ChargedFees(feeAmount);
        }
    }

    function _swapNativeToWant() internal virtual {
        if (depositToken == address(0)) {
            _swap(NATIVE, want);
        } else {
            if (depositToken != NATIVE) {
                _swap(NATIVE, depositToken);
            }
            _swap(depositToken, want);
        }
    }

    function _swap(address tokenFrom, address tokenTo) internal {
        uint256 bal = IERC20(tokenFrom).balanceOf(address(this));
        _swap(tokenFrom, tokenTo, bal);
    }

    // Uses 4-arg swap (minAmountOut=0) so no oracle is needed.
    // Acceptable for hackathon; add oracle-based slippage protection in production.
    function _swap(address tokenFrom, address tokenTo, uint256 amount) internal {
        if (amount > 0 && tokenFrom != tokenTo) {
            IERC20(tokenFrom).forceApprove(swapper, amount);
            IBeefySwapper(swapper).swap(tokenFrom, tokenTo, amount, 0);
        }
    }

    function rewardsLength() external view returns (uint256) {
        return rewards.length;
    }

    function addReward(address _token) public onlyManager {
        require(_token != want, "!want");
        require(_token != NATIVE, "!native");
        _verifyRewardToken(_token);
        rewards.push(_token);
    }

    function removeReward(uint256 i) external onlyManager {
        rewards[i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    function resetRewards() external onlyManager {
        delete rewards;
    }

    function setRewardMinAmount(address token, uint256 minAmount) external onlyManager {
        minAmounts[token] = minAmount;
    }

    function setDepositToken(address token) public onlyManager {
        if (token == address(0)) {
            depositToken = address(0);
            return;
        }
        require(token != want, "!want");
        _verifyRewardToken(token);
        depositToken = token;
    }

    function lockedProfit() public view returns (uint256) {
        if (lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < lockDuration ? lockDuration - elapsed : 0;
        return totalLocked * remaining / lockDuration;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            lockDuration = 0;
        } else {
            lockDuration = 1 days;
        }
    }

    function setLockDuration(uint256 _duration) external onlyManager {
        lockDuration = _duration;
    }

    function rewardsAvailable() external view virtual returns (uint256) {
        return 0;
    }

    function callReward() external view virtual returns (uint256) {
        return 0;
    }

    function depositFee() public view virtual returns (uint256) {
        return 0;
    }

    function withdrawFee() public view virtual returns (uint256) {
        return 0;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _emergencyWithdraw();
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(want).transfer(vault, balanceOfWant());
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public virtual onlyManager {
        pause();
        _emergencyWithdraw();
    }

    function pause() public virtual onlyManager {
        _pause();
    }

    function unpause() external virtual onlyManager {
        _unpause();
        deposit();
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = _swapper;
        emit SetSwapper(_swapper);
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
        emit SetStrategist(_strategist);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    receive() external payable {}

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[49] private __gap;
}
