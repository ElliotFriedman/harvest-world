// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HarvestDeployer} from "./deployers/HarvestDeployer.sol";

contract Deploy is Script {
    using stdJson for string;

    function run() external {
        string memory json = vm.readFile("addresses/480.json");

        address usdc = json.readAddress(".tokens.USDC");
        address morphoVaultAddr = json.readAddress(".morpho.re7USDCVault");
        address merklDistributor = json.readAddress(".merkl.distributor");
        address morphoToken = json.readAddress(".tokens.MORPHO");

        address strategyFactory = vm.envAddress("STRATEGY_FACTORY");
        address beefySwapper = vm.envAddress("BEEFY_SWAPPER");
        address strategistAddr = vm.envAddress("STRATEGIST");

        address[] memory rewards = new address[](1);
        rewards[0] = morphoToken;

        HarvestDeployer.ExternalAddresses memory ext = HarvestDeployer.ExternalAddresses({
            want: usdc,
            depositToken: address(0),
            morphoVault: morphoVaultAddr,
            claimer: merklDistributor,
            strategyFactory: strategyFactory,
            swapper: beefySwapper,
            strategist: strategistAddr
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo World Morpho USDC",
            vaultSymbol: "mooWorldMorphoUSDC",
            harvestOnDeposit: true,
            rewards: rewards,
            externalNullifierHash: vm.envUint("WORLD_ID_EXTERNAL_NULLIFIER_HASH")
        });

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        HarvestDeployer.Deployment memory d = HarvestDeployer.deploy(ext, params);

        vm.stopBroadcast();

        console.log("Vault:    ", address(d.vault));
        console.log("Strategy: ", address(d.strategy));
    }
}
