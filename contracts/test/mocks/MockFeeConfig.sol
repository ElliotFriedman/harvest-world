// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFeeConfig} from "../../src/interfaces/IFeeConfig.sol";

contract MockFeeConfig is IFeeConfig {
    FeeCategory private _fees;
    mapping(address => uint256) private _feeIds;

    constructor() {
        // 4.5% total: 32% to beefy, 11% to caller, 11% to strategist
        // All scaled by DIVISOR (1 ether) as the strategy expects
        _fees = FeeCategory({
            total: 0.045 ether,
            beefy: 0.32 ether,
            call: 0.11 ether,
            strategist: 0.11 ether,
            label: "default",
            active: true
        });
    }

    function getFees(address) external view override returns (FeeCategory memory) {
        return _fees;
    }

    function stratFeeId(address strategy) external view override returns (uint256) {
        return _feeIds[strategy];
    }

    function setStratFeeId(uint256 feeId) external override {
        _feeIds[msg.sender] = feeId;
    }

    function setFees(FeeCategory calldata fees) external {
        _fees = fees;
    }
}
