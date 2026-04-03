// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HarvestDeployer} from "./deployers/HarvestDeployer.sol";
import {BeefySwapper} from "../src/BeefySwapper.sol";

contract Deploy is Script {
    using stdJson for string;

    /// @dev SwapRouter02 exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))
    bytes4 internal constant EXACT_INPUT_SINGLE = 0x04e45aaf;

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

    /// @dev World ID action name — must match the action created in the Developer Portal.
    string internal constant WORLD_ID_ACTION = "verify-human";

    /// @dev Compute the World ID external nullifier hash from app_id + action.
    ///      Formula: hashToField(abi.encodePacked(hashToField(abi.encodePacked(app_id)), action))
    function _computeExternalNullifierHash(string memory appId) internal pure returns (uint256) {
        uint256 appIdHash = uint256(keccak256(abi.encodePacked(appId))) >> 8;
        return uint256(keccak256(abi.encodePacked(appIdHash, WORLD_ID_ACTION))) >> 8;
    }

    function run() external {
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile("addresses/480.json");

        address usdc = _findAddress(json, "USDC");
        address weth = _findAddress(json, "WETH");
        address morphoVaultAddr = _findAddress(json, "MORPHO_RE7_USDC_VAULT");
        address merklDistributor = _findAddress(json, "MERKL_DISTRIBUTOR");
        address wld = _findAddress(json, "WLD");
        address uniV3Router = _findAddress(json, "UNISWAP_V3_SWAP_ROUTER_02");

        // Compute World ID external nullifier hash from APP_ID env var
        string memory appId = vm.envString("APP_ID");
        uint256 externalNullifierHash = _computeExternalNullifierHash(appId);
        console.log("ExternalNullifier:", externalNullifierHash);

        address[] memory rewards = new address[](1);
        rewards[0] = wld;

        vm.startBroadcast();

        // ── 1. Deploy BeefySwapper ──────────────────────────────────────────
        // No oracle needed — strategy always calls swap(from, to, amount, 0)
        BeefySwapper swapper = new BeefySwapper();
        swapper.initialize(address(0), 0);

        // ── 2. Configure Uniswap V3 swap routes ────────────────────────────
        //
        // exactInputSingle calldata layout (228 bytes):
        //   [0:4]     selector 0x04e45aaf
        //   [4:36]    tokenIn
        //   [36:68]   tokenOut
        //   [68:100]  fee (uint24)
        //   [100:132] recipient (= swapper, it relays tokens)
        //   [132:164] amountIn         ← replaced at amountIndex
        //   [164:196] amountOutMinimum ← replaced at minIndex
        //   [196:228] sqrtPriceLimitX96 (0 = no limit)

        _setUniV3Route(swapper, uniV3Router, wld, weth, 3000); // 0.3% — WLD/WETH pool has liquidity
        _setUniV3Route(swapper, uniV3Router, weth, usdc, 500); // 0.05% — WETH/USDC pool has liquidity

        // ── 3. Deploy vault + strategy ──────────────────────────────────────
        HarvestDeployer.ExternalAddresses memory ext = HarvestDeployer.ExternalAddresses({
            want: usdc,
            depositToken: address(0),
            morphoVault: morphoVaultAddr,
            claimer: merklDistributor,
            swapper: address(swapper),
            strategist: msg.sender,
            feeRecipient: msg.sender
        });

        HarvestDeployer.DeployParams memory params = HarvestDeployer.DeployParams({
            vaultName: "Moo World Morpho USDC",
            vaultSymbol: "mooWorldMorphoUSDC",
            harvestOnDeposit: true,
            rewards: rewards,
            externalNullifierHash: externalNullifierHash
        });

        HarvestDeployer.Deployment memory d = HarvestDeployer.deploy(ext, params);

        vm.stopBroadcast();

        console.log("BeefySwapper:     ", address(swapper));
        console.log("Vault:            ", address(d.vault));
        console.log("Strategy:         ", address(d.strategy));
    }

    /// @dev Register a Uniswap V3 exactInputSingle route in the swapper.
    function _setUniV3Route(BeefySwapper swapper, address router, address tokenIn, address tokenOut, uint24 fee)
        internal
    {
        bytes memory data = abi.encodeWithSelector(
            EXACT_INPUT_SINGLE,
            tokenIn,
            tokenOut,
            fee,
            address(swapper), // recipient — swapper relays output back to caller
            uint256(0), // amountIn placeholder (overwritten at index 132)
            uint256(0), // amountOutMinimum placeholder (overwritten at index 164)
            uint160(0) // sqrtPriceLimitX96 — 0 means no limit
        );

        swapper.setSwapInfo(
            tokenIn,
            tokenOut,
            BeefySwapper.SwapInfo({
                router: router,
                data: data,
                amountIndex: 132, // 4 (selector) + 4×32 (fields before amountIn)
                minIndex: 164, // 4 (selector) + 5×32 (fields before amountOutMinimum)
                minAmountSign: 0 // positive
            })
        );
    }
}
