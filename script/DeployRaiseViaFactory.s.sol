// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {CradleFactory} from "../src/CradleFactory.sol";
import {CradleRaise} from "../src/CradleRaise.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {StdUtils} from "forge-std/StdUtils.sol"; // For parsing bytes32

/**
 * @notice Script to deploy a CradleRaise instance via an existing CradleFactory.
 * @dev Reads parameters from environment variables with defaults for local Anvil testing.
 * Required ENV Vars (or defaults will be used):
 *  - DEPLOYER_PRIVATE_KEY (or default Anvil key 0)
 *  - FACTORY_ADDRESS (default assumes local deployment)
 *  - TOKEN_SOLD_ADDRESS (default assumes local mock)
 *  - ACCEPTED_TOKEN_ADDRESS (default assumes local mock)
 *  - RAISE_PRICE_PER_TOKEN_NATIVE (e.g., "0.1" for 0.1 AcceptedToken per 1 TokenSold)
 *  - RAISE_PRESALE_START_OFFSET (seconds, default 1 hour)
 *  - RAISE_PUBLICSALE_START_OFFSET (seconds, default 2 hours)
 *  - RAISE_END_OFFSET (seconds, default 7 days)
 *  - RAISE_MERKLE_ROOT (bytes32 hex string, default bytes32(0))
 *  - RAISE_OWNER_ADDRESS (default deployer)
 *  - RAISE_FEE_RECIPIENT_ADDRESS (default deployer)
 *  - RAISE_FEE_BPS (basis points, default 500)
 *  - RAISE_MAX_RAISE_ACCEPTED_NATIVE (human-readable, e.g., "100000" for 100k AcceptedToken)
 *  - RAISE_MIN_ALLOC_TOKEN_NATIVE (human-readable, e.g., "100" for 100 TokenSold)
 *  - RAISE_MAX_ALLOC_TOKEN_NATIVE (human-readable, e.g., "1000" for 1000 TokenSold)
 */
contract DeployRaiseViaFactory is Script {

    // Default LOCAL Anvil addresses (Update if mocks are redeployed locally)
    address constant LOCAL_FACTORY_ADDRESS = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
    address constant LOCAL_TOKEN_SOLD_ADDRESS = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; // Mock TKN
    address constant LOCAL_ACCEPTED_TOKEN_ADDRESS = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0; // Mock USDC

    // Sonic Testnet Addresses (Keep for reference, but script loads from ENV now for flexibility)
    address constant SONIC_TESTNET_WETH_ADDRESS = 0x309C92261178fA0CF748A855e90Ae73FDb79EBc7;
    address constant SONIC_TESTNET_WS_ADDRESS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;

    uint256 constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (address) {
        console2.log("--- Starting DeployRaiseViaFactory Script (ENV Config) ---");

        // --- Configuration Loading from ENV ---
        uint256 deployerPrivateKey;
        address factoryAddress;
        address tokenSoldAddress;
        address acceptedTokenAddress;
        address deployerAddress;

        // Determine network and select appropriate key and default addresses
        if (block.chainid == 57054) { // Sonic Testnet
            console2.log("Targeting Sonic Testnet (Chain ID 57054)");
            deployerPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");
            if (deployerPrivateKey == 0) revert("TESTNET_PRIVATE_KEY env var not set for Sonic Testnet");
            deployerAddress = vm.addr(deployerPrivateKey);
            factoryAddress = vm.envAddress("FACTORY_ADDRESS");
            tokenSoldAddress = vm.envAddress("TOKEN_SOLD_ADDRESS");
            acceptedTokenAddress = vm.envAddress("ACCEPTED_TOKEN_ADDRESS");
            if (factoryAddress == address(0)) revert("FACTORY_ADDRESS env var not set for Sonic Testnet");
            if (tokenSoldAddress == address(0)) revert("TOKEN_SOLD_ADDRESS env var not set for Sonic Testnet");
            if (acceptedTokenAddress == address(0)) revert("ACCEPTED_TOKEN_ADDRESS env var not set for Sonic Testnet");
            console2.log("Using Addresses from ENV for Testnet");
        } else { // Default to local Anvil or other networks
            console2.log("Targeting local network (Chain ID: %s) or unknown network.", block.chainid);
            uint256 localPrivateKey = vm.envUint("PRIVATE_KEY"); 
            deployerPrivateKey = (localPrivateKey != 0) ? localPrivateKey : DEFAULT_ANVIL_PRIVATE_KEY;
            deployerAddress = vm.addr(deployerPrivateKey);
            factoryAddress = vm.envOr("FACTORY_ADDRESS", LOCAL_FACTORY_ADDRESS);
            tokenSoldAddress = vm.envOr("TOKEN_SOLD_ADDRESS", LOCAL_TOKEN_SOLD_ADDRESS);
            acceptedTokenAddress = vm.envOr("ACCEPTED_TOKEN_ADDRESS", LOCAL_ACCEPTED_TOKEN_ADDRESS);
            console2.log("Using Addresses from ENV or local defaults.");
        }

        console2.log("Using Deployer Address:", deployerAddress);
        console2.log("Using Factory Address:", factoryAddress);
        console2.log("Using Token Sold Address:", tokenSoldAddress);
        console2.log("Using Accepted Token Address:", acceptedTokenAddress);

        // --- Load Remaining Parameters from Environment ---
        uint256 pricePerTokenScaled = vm.envUint("RAISE_PRICE_PER_TOKEN_SCALED");
        if (pricePerTokenScaled == 0) revert("RAISE_PRICE_PER_TOKEN_SCALED must be set in .env");

        uint256 presaleStartOffset = vm.envUint("RAISE_PRESALE_START_OFFSET"); 
        uint256 publicSaleStartOffset = vm.envUint("RAISE_PUBLICSALE_START_OFFSET"); 
        uint256 endOffset = vm.envUint("RAISE_END_OFFSET");
        if (endOffset == 0) revert("RAISE_END_OFFSET must be set in .env");

        bytes32 merkleRoot = vm.envBytes32("RAISE_MERKLE_ROOT"); 

        uint256 maxRaiseAcceptedScaled = vm.envUint("RAISE_MAX_RAISE_ACCEPTED_SCALED");
        if (maxRaiseAcceptedScaled == 0) revert("RAISE_MAX_RAISE_ACCEPTED_SCALED must be set in .env");

        uint256 minAllocTokenScaled = vm.envUint("RAISE_MIN_ALLOC_TOKEN_SCALED");
        if (minAllocTokenScaled == 0) revert("RAISE_MIN_ALLOC_TOKEN_SCALED must be set in .env");

        uint256 maxAllocTokenScaled = vm.envUint("RAISE_MAX_ALLOC_TOKEN_SCALED");
        if (maxAllocTokenScaled == 0) revert("RAISE_MAX_ALLOC_TOKEN_SCALED must be set in .env");

        // Calculate absolute timestamps
        uint256 currentTime = block.timestamp;
        uint256 presaleStartTime = currentTime + presaleStartOffset;
        uint256 publicSaleStartTime = currentTime + publicSaleStartOffset;
        uint256 endTime = currentTime + endOffset;

        // Log parameters for verification
        console2.log("--- Raise Parameters (from ENV) ---");
        console2.log("Token Sold (TKN):", tokenSoldAddress);
        console2.log("Accepted Token (ACC):", acceptedTokenAddress);
        console2.log("Price (ACC base units per TKN whole unit):", pricePerTokenScaled);
        console2.log("Presale Start Time:", presaleStartTime);
        console2.log("Public Sale Start Time:", publicSaleStartTime);
        console2.log("End Time:", endTime);
        console2.log("Merkle Root:", vm.toString(merkleRoot));

        // Load owner/recipient, defaulting to deployerAddress derived from the loaded key
        address raiseOwner = vm.envOr("RAISE_OWNER_ADDRESS", deployerAddress);
        address feeRecipient = vm.envOr("RAISE_FEE_RECIPIENT_ADDRESS", deployerAddress);
        uint16 feeBps = uint16(vm.envOr("RAISE_FEE_BPS", uint256(500)));

        // --- Deployment via Factory ---
        vm.startBroadcast(deployerPrivateKey); // Use the loaded key

        CradleFactory factory = CradleFactory(payable(factoryAddress));
        address newRaiseAddress = factory.createRaise(
            tokenSoldAddress,
            acceptedTokenAddress,
            pricePerTokenScaled,
            presaleStartTime,
            publicSaleStartTime,
            endTime,
            merkleRoot,
            raiseOwner,
            feeRecipient,
            feeBps,
            maxRaiseAcceptedScaled,
            minAllocTokenScaled,
            maxAllocTokenScaled
        );

        vm.stopBroadcast();

        console2.log("--- Deployment Result ---");
        console2.log("New CradleRaise instance deployed at:", newRaiseAddress);

        // --- Post-Deployment Checks & Asserts ---
        // Perform some basic checks to ensure the deployed raise has the correct parameters
        CradleRaise newRaise = CradleRaise(payable(newRaiseAddress));

        console2.log("--- Verifying Deployed Raise Parameters ---");
        assert(address(newRaise.token()) == tokenSoldAddress);                // FIX: Cast IERC20 to address for comparison
        assert(address(newRaise.acceptedToken()) == acceptedTokenAddress);      // FIX: Cast IERC20 to address for comparison
        assert(newRaise.pricePerToken() == pricePerTokenScaled);                // Check Price
        assert(newRaise.presaleStart() == presaleStartTime);                  // Check Presale Start Time
        assert(newRaise.publicSaleStart() == publicSaleStartTime);              // Check Public Sale Start Time
        assert(newRaise.endTime() == endTime);                              // Check End Time
        assert(newRaise.merkleRoot() == merkleRoot);                        // Check Merkle Root
        assert(newRaise.feeRecipient() == feeRecipient);                    // Check Fee Recipient
        assert(newRaise.feePercentBasisPoints() == feeBps);                 // Check Fee Basis Points
        assert(newRaise.maxAcceptedTokenRaise() == maxRaiseAcceptedScaled);     // Check Hard Cap
        assert(newRaise.minTokenAllocation() == minAllocTokenScaled);         // FIX: Check Min Allocation (use correct getter)
        assert(newRaise.maxTokenAllocation() == maxAllocTokenScaled);         // FIX: Check Max Allocation (use correct getter)
        assert(newRaise.owner() == raiseOwner);                             // Check Owner

        console2.log("Deployed Raise Parameters Verified Successfully.");

        // Update .env file (Manually for now, or via script output)
        // TODO: Consider adding script logic to update .env automatically?
        console2.log("--- Deployment Complete ---");
        console2.log("ACTION REQUIRED: Update RAISE_ADDRESS in your .env file:");
        console2.log("RAISE_ADDRESS=%s", newRaiseAddress);

        return newRaiseAddress;
    }
} 