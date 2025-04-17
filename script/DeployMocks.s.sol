// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../test/CradleRaise.t.sol"; // Import from test file
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // Needed for interface checks potentially

/**
 * @notice Script to deploy Mock ERC20 tokens for local testing.
 * @dev Reads deployer key and mock token parameters from environment variables.
 * ENV Vars:
 *  - DEPLOYER_PRIVATE_KEY (or default Anvil key 0)
 *  - MOCK_TKN_SOLD_NAME (string, default "Mock Token Sold")
 *  - MOCK_TKN_SOLD_SYMBOL (string, default "mTKN")
 *  - MOCK_TKN_SOLD_DECIMALS (uint8, default 18)
 *  - MOCK_TKN_ACCEPTED_NAME (string, default "Mock USDC")
 *  - MOCK_TKN_ACCEPTED_SYMBOL (string, default "mUSDC")
 *  - MOCK_TKN_ACCEPTED_DECIMALS (uint8, default 6)
 */
contract DeployMocks is Script {
    uint256 constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (address, address) {
        console2.log("--- Starting DeployMocks Script ---");

        // --- Configuration ---
        uint256 deployerPrivateKey;
        address deployerAddress;

        // Determine network and select appropriate key
        if (block.chainid == 57054) {
            // Sonic Testnet
            console2.log("Targeting Sonic Testnet (Chain ID 57054)");
            deployerPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");
            if (deployerPrivateKey == 0) revert("TESTNET_PRIVATE_KEY env var not set or invalid for Sonic Testnet");
            deployerAddress = vm.addr(deployerPrivateKey);
        } else {
            // Default to local Anvil or other networks
            console2.log("Targeting local network (Chain ID: %s) or unknown network.", block.chainid);
            uint256 localPrivateKey = vm.envUint("PRIVATE_KEY");
            deployerPrivateKey = (localPrivateKey != 0) ? localPrivateKey : DEFAULT_ANVIL_PRIVATE_KEY;
            deployerAddress = vm.addr(deployerPrivateKey);
        }

        console2.log("Using Deployer Address:", deployerAddress);

        // Load token parameters from ENV (with defaults for local)
        string memory tokenSoldName = vm.envOr("MOCK_TKN_SOLD_NAME", string("Mock Token Sold"));
        string memory tokenSoldSymbol = vm.envOr("MOCK_TKN_SOLD_SYMBOL", string("mTKN"));
        uint8 tokenSoldDecimals = uint8(vm.envOr("MOCK_TKN_SOLD_DECIMALS", uint256(18)));

        string memory acceptedTokenName = vm.envOr("MOCK_TKN_ACCEPTED_NAME", string("Mock USDC"));
        string memory acceptedTokenSymbol = vm.envOr("MOCK_TKN_ACCEPTED_SYMBOL", string("mUSDC"));
        uint8 acceptedTokenDecimals = uint8(vm.envOr("MOCK_TKN_ACCEPTED_DECIMALS", uint256(6)));

        console2.log("--- Deploying Mock Tokens ---");
        console2.log("  Token Sold: %s (%s) %d decimals", tokenSoldName, tokenSoldSymbol, tokenSoldDecimals);
        console2.log(
            "  Accepted Token: %s (%s) %d decimals", acceptedTokenName, acceptedTokenSymbol, acceptedTokenDecimals
        );

        // --- Deployment ---
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 tokenSold = new MockERC20(tokenSoldName, tokenSoldSymbol, tokenSoldDecimals);
        MockERC20 acceptedToken = new MockERC20(acceptedTokenName, acceptedTokenSymbol, acceptedTokenDecimals);

        vm.stopBroadcast();

        console2.log("Mock Token Sold deployed at:", address(tokenSold));
        console2.log("Mock Accepted Token deployed at:", address(acceptedToken));

        return (address(tokenSold), address(acceptedToken));
    }
}
