// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorphoMerkl} from "../../src/StrategyMorphoMerkl.sol";
import {BaseAllToNativeFactoryStrat} from "../../src/BaseAllToNativeFactoryStrat.sol";
import {IStrategyV7} from "../../src/interfaces/IStrategyV7.sol";

library HarvestDeployer {
    struct ExternalAddresses {
        address want;            // e.g. USDC
        address depositToken;    // address(0) for same-as-want
        address morphoVault;     // IERC4626
        address claimer;         // IMerklClaimer
        address swapper;         // IBeefySwapper
        address strategist;
        address feeRecipient;
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
        StrategyMorphoMerkl strategy;
    }

    function deploy(ExternalAddresses memory ext, DeployParams memory params)
        internal returns (Deployment memory d)
    {
        // 1. Deploy vault (uninitialized — no strategy yet)
        d.vault = new BeefyVaultV7();

        // 2. Deploy strategy
        d.strategy = new StrategyMorphoMerkl();

        // 3. Initialize strategy
        BaseAllToNativeFactoryStrat.Addresses memory addrs = BaseAllToNativeFactoryStrat.Addresses({
            want: ext.want,
            depositToken: ext.depositToken,
            vault: address(d.vault),
            swapper: ext.swapper,
            strategist: ext.strategist,
            feeRecipient: ext.feeRecipient
        });
        d.strategy.initialize(
            ext.morphoVault,
            ext.claimer,
            params.harvestOnDeposit,
            params.rewards,
            addrs
        );

        // 4. Initialize vault
        d.vault.initialize(
            IStrategyV7(address(d.strategy)),
            params.vaultName,
            params.vaultSymbol,
            params.externalNullifierHash
        );
    }
}
