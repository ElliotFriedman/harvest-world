// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../src/interfaces/IMerklClaimer.sol";

contract MockMerklClaimer is IMerklClaimer {
    uint256 public claimCallCount;

    function claim(address[] calldata, address[] calldata, uint256[] calldata, bytes32[][] calldata) external override {
        claimCallCount++;
    }
}
