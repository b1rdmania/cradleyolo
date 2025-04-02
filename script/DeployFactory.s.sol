// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {CradleFactory} from "../src/CradleFactory.sol";

/**
 * @notice Script to deploy the CradleFactory contract.
 * @dev Reads deployer key and optional initial owner from environment variables.
 * ENV Vars:
 *  - PRIVATE_KEY (or default Anvil key 0)
 *  - TESTNET_PRIVATE_KEY (for Sonic Testnet)
 *  - FACTORY_INITIAL_OWNER (address, defaults to deployer)
 */
contract DeployFactory is Script {

    uint256 constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (CradleFactory) {
        console2.log("--- Starting DeployFactory Script ---");

        // --- Configuration --- 
        uint256 deployerPrivateKey;
        address initialOwner;
        address deployerAddress;

        // Determine network and select appropriate key
        if (block.chainid == 57054) { // Sonic Testnet
            console2.log("Targeting Sonic Testnet (Chain ID 57054)");
            deployerPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");
            if (deployerPrivateKey == 0) revert("TESTNET_PRIVATE_KEY env var not set or invalid for Sonic Testnet");
            deployerAddress = vm.addr(deployerPrivateKey);
        } else { // Default to local Anvil or other networks
            console2.log("Targeting local network (Chain ID: %s) or unknown network.", block.chainid);
            uint256 localPrivateKey = vm.envUint("PRIVATE_KEY"); 
            deployerPrivateKey = (localPrivateKey != 0) ? localPrivateKey : DEFAULT_ANVIL_PRIVATE_KEY;
            deployerAddress = vm.addr(deployerPrivateKey); 
        }
        
        console2.log("Using Deployer Address:", deployerAddress);

        // Determine initial owner: use env var if set, otherwise default to deployer
        initialOwner = vm.envOr("FACTORY_INITIAL_OWNER", deployerAddress); // Use envOr for optional override
        console2.log("Setting Initial Factory Owner:", initialOwner);

        // --- Deployment ---
        vm.startBroadcast(deployerPrivateKey);

        CradleFactory factory = new CradleFactory(initialOwner);

        vm.stopBroadcast();

        console2.log("CradleFactory deployed at:", address(factory));
        console2.log("Factory Owner:", factory.owner());

        return factory;
    }
} 