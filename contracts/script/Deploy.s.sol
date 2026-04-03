// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HarvestDeployer} from "./deployers/HarvestDeployer.sol";

contract Deploy is Script {
    using stdJson for string;

    function _findAddress(string memory json, string memory name) internal pure returns (address) {
        // Parse the array and find the entry with matching name
        bytes memory rawEntries = json.parseRaw("$");
        Entry[] memory entries = abi.decode(rawEntries, (Entry[]));
        for (uint256 i; i < entries.length; i++) {
            if (keccak256(bytes(entries[i].name)) == keccak256(bytes(name))) {
                return entries[i].addr;
            }
        }
        revert(string.concat("Address not found: ", name));
    }

    struct Entry {
        address addr;
        bool isContract;
        string name;
    }

    function run() external {
        string memory json = vm.readFile("addresses/480.json");

        address usdc = _findAddress(json, "USDC");
        address morphoVaultAddr = _findAddress(json, "MORPHO_RE7_USDC_VAULT");
        address merklDistributor = _findAddress(json, "MERKL_DISTRIBUTOR");
        address morphoToken = _findAddress(json, "MORPHO");

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
