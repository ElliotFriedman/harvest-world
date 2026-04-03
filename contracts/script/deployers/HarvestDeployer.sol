// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorpho} from "../../src/StrategyMorpho.sol";
import {BaseAllToNativeFactoryStrat} from "../../src/BaseAllToNativeFactoryStrat.sol";
import {IStrategyV7} from "../../src/interfaces/IStrategyV7.sol";

library HarvestDeployer {
    struct ExternalAddresses {
        address want; // e.g. USDC
        address depositToken; // address(0) for same-as-want
        address morphoVault; // IERC4626
        address claimer; // IMerklClaimer
        address strategyFactory; // IStrategyFactory
        address swapper; // IBeefySwapper
        address strategist;
    }

    struct DeployParams {
        string vaultName;
        string vaultSymbol;
        bool harvestOnDeposit;
        address[] rewards;
        uint256 externalNullifierHash; // World ID: hash of app_id + action
    }

    struct Deployment {
        BeefyVaultV7 vault;
        StrategyMorpho strategy;
    }

    function deploy(ExternalAddresses memory ext, DeployParams memory params) internal returns (Deployment memory d) {
        // 1. Deploy vault (uninitialized — no strategy yet)
        d.vault = new BeefyVaultV7();

        // 2. Deploy strategy implementation (uninitialized)
        d.strategy = new StrategyMorpho();

        // 3. Initialize strategy — it now knows its vault address
        BaseAllToNativeFactoryStrat.Addresses memory addrs = BaseAllToNativeFactoryStrat.Addresses({
            want: ext.want,
            depositToken: ext.depositToken,
            factory: ext.strategyFactory,
            vault: address(d.vault),
            swapper: ext.swapper,
            strategist: ext.strategist
        });
        d.strategy.initialize(ext.morphoVault, ext.claimer, params.harvestOnDeposit, params.rewards, addrs);

        // 4. Initialize vault — it now knows its strategy
        d.vault
            .initialize(
                IStrategyV7(address(d.strategy)), params.vaultName, params.vaultSymbol, params.externalNullifierHash
            );
    }
}
