// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HarvestDeployer} from "./deployers/HarvestDeployer.sol";
import {MockBeefySwapper} from "../test/mocks/MockBeefySwapper.sol";

contract Deploy is Script {
    using stdJson for string;

    struct Entry {
        address addr;
        bool isContract;
        string name;
    }

    function _findAddress(string memory json, string memory name) internal pure returns (address) {
        bytes memory rawEntries = json.parseRaw("$");
        Entry[] memory entries = abi.decode(rawEntries, (Entry[]));
        for (uint256 i; i < entries.length; i++) {
            if (keccak256(bytes(entries[i].name)) == keccak256(bytes(name))) {
                return entries[i].addr;
            }
        }
        revert(string.concat("Address not found: ", name));
    }

    function run() external {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile("addresses/480.json");

        address usdc = _findAddress(json, "USDC");
        address morphoVaultAddr = _findAddress(json, "MORPHO_RE7_USDC_VAULT");
        address merklDistributor = _findAddress(json, "MERKL_DISTRIBUTOR");
        address morphoToken = _findAddress(json, "MORPHO_TOKEN");

        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        address[] memory rewards = new address[](1);
        rewards[0] = morphoToken;

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // MockBeefySwapper for hackathon — replace with real BeefySwapper + Uniswap V3 routes in production
        MockBeefySwapper swapper = new MockBeefySwapper();

        HarvestDeployer.ExternalAddresses memory ext = HarvestDeployer.ExternalAddresses({
            want: usdc,
            depositToken: address(0),
            morphoVault: morphoVaultAddr,
            claimer: merklDistributor,
            swapper: address(swapper),
            strategist: deployer,
            feeRecipient: deployer
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo World Morpho USDC",
            vaultSymbol: "mooWorldMorphoUSDC",
            harvestOnDeposit: true,
            rewards: rewards,
            externalNullifierHash: vm.envUint("WORLD_ID_EXTERNAL_NULLIFIER_HASH")
        });

        HarvestDeployer.Deployment memory d = HarvestDeployer.deploy(ext, params);

        vm.stopBroadcast();

        console.log("BeefySwapper:     ", address(swapper));
        console.log("Vault:            ", address(d.vault));
        console.log("Strategy:         ", address(d.strategy));
    }
}
