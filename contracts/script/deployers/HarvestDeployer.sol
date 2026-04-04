// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin-4/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {BeefyVaultV7} from "../../src/BeefyVaultV7.sol";
import {StrategyMorphoMerkl} from "../../src/StrategyMorphoMerkl.sol";
import {BaseAllToNativeFactoryStrat} from "../../src/BaseAllToNativeFactoryStrat.sol";
import {IStrategyV7} from "../../src/interfaces/IStrategyV7.sol";

library HarvestDeployer {
    struct ExternalAddresses {
        address want; // e.g. USDC
        address depositToken; // address(0) for same-as-want
        address morphoVault; // IERC4626
        address claimer; // IMerklClaimer
        address swapper; // IBeefySwapper
        address strategist;
        address feeRecipient;
    }

    struct DeployParams {
        string vaultName;
        string vaultSymbol;
        bool harvestOnDeposit;
        address[] rewards;
    }

    struct Deployment {
        BeefyVaultV7 vault;
        StrategyMorphoMerkl strategy;
    }

    /// @param proxyAdmin Address that controls proxy upgrades (EOA in tests, ProxyAdmin contract in prod).
    function deploy(ExternalAddresses memory ext, DeployParams memory params, address proxyAdmin)
        internal
        returns (Deployment memory d)
    {
        // 1. Deploy logic contracts (initializers disabled — cannot be called directly)
        BeefyVaultV7 vaultImpl = new BeefyVaultV7();
        StrategyMorphoMerkl stratImpl = new StrategyMorphoMerkl();

        // 2. Deploy proxies with no init data so both addresses are known before either is initialized.
        //    This resolves the chicken-and-egg: strategy needs vault address; vault needs strategy address.
        d.vault = BeefyVaultV7(address(new TransparentUpgradeableProxy(address(vaultImpl), proxyAdmin, "")));
        d.strategy = StrategyMorphoMerkl(payable(new TransparentUpgradeableProxy(address(stratImpl), proxyAdmin, "")));

        // 3. Initialize strategy (vault proxy address is now known)
        BaseAllToNativeFactoryStrat.Addresses memory addrs = BaseAllToNativeFactoryStrat.Addresses({
            want: ext.want,
            depositToken: ext.depositToken,
            vault: address(d.vault),
            swapper: ext.swapper,
            strategist: ext.strategist,
            feeRecipient: ext.feeRecipient
        });
        d.strategy.initialize(ext.morphoVault, ext.claimer, params.harvestOnDeposit, params.rewards, addrs);

        // 4. Initialize vault (strategy proxy address is now known)
        d.vault.initialize(IStrategyV7(address(d.strategy)), params.vaultName, params.vaultSymbol);
    }
}
