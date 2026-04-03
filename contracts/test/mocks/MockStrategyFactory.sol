// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../src/interfaces/IStrategyFactory.sol";

contract MockStrategyFactory is IStrategyFactory {
    address public override native;
    address public override keeper;
    address public override beefyFeeRecipient;
    address public override beefyFeeConfig;
    bool public override globalPause;
    mapping(string => bool) private _strategyPause;

    constructor(
        address _native,
        address _keeper,
        address _beefyFeeRecipient,
        address _beefyFeeConfig
    ) {
        native = _native;
        keeper = _keeper;
        beefyFeeRecipient = _beefyFeeRecipient;
        beefyFeeConfig = _beefyFeeConfig;
    }

    function createStrategy(string calldata) external pure override returns (address) {
        revert("MockStrategyFactory: not implemented");
    }

    function strategyPause(string calldata stratName) external view override returns (bool) {
        return _strategyPause[stratName];
    }

    // Test helpers
    function setGlobalPause(bool _paused) external { globalPause = _paused; }
    function setStrategyPause(string calldata stratName, bool _paused) external {
        _strategyPause[stratName] = _paused;
    }
    function setKeeper(address _keeper) external { keeper = _keeper; }
    function setBeefyFeeRecipient(address _recipient) external { beefyFeeRecipient = _recipient; }
    function setBeefyFeeConfig(address _config) external { beefyFeeConfig = _config; }
}
