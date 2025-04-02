// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {CradleFactory} from "../src/CradleFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // Import Ownable for error reference
// We might need CradleRaise later if testing the deployment results more deeply
// import {CradleRaise} from "../src/CradleRaise.sol"; 

contract CradleFactoryTest is Test {
    // --- State Variables ---
    CradleFactory internal factory;
    address internal owner; // The owner set during setup
    address internal user1; // A non-owner address for testing permissions
    address internal projectWallet; // The address intended to own the deployed CradleRaise

    // Test deployment parameters (can be adjusted)
    address internal dummyToken = address(0x1);
    address internal dummyAcceptedToken = address(0x2);
    uint256 internal dummyPrice = 1 * 10**6; // e.g., 1 USDC (6 decimals)
    uint256 internal dummyPresaleStart;
    uint256 internal dummyPublicSaleStart;
    uint256 internal dummyEndTime;
    bytes32 internal dummyMerkleRoot = bytes32(0);
    address internal dummyFeeRecipient = address(0x3);
    uint16  internal dummyFeeBps = 500; // 5%
    uint256 internal dummyMaxRaise = 100_000 * 10**6; // e.g., 100k USDC
    uint256 internal dummyMinAlloc = 100 * 10**18;  // e.g., 100 Tokens (18 decimals)
    uint256 internal dummyMaxAlloc = 1000 * 10**18; // e.g., 1000 Tokens (18 decimals)

    // --- Setup ---

    function setUp() public virtual {
        owner = makeAddr("factoryOwner");
        user1 = makeAddr("user1");
        projectWallet = makeAddr("projectWallet");

        // Set default timestamps relative to current block
        dummyPresaleStart = block.timestamp + 1 days;
        dummyPublicSaleStart = block.timestamp + 2 days;
        dummyEndTime = block.timestamp + 10 days;

        // Deploy the factory, making 'owner' the factory owner
        vm.prank(owner); // Subsequent calls by 'owner'
        factory = new CradleFactory(owner);
    }

    // --- Test Functions ---

    /**
     * @notice Test if the factory deployment sets the owner correctly.
     */
    function test_Factory_Deployment_SetsOwner() public view {
        assertEq(factory.owner(), owner, "Factory owner should be set correctly on deployment");
    }

    /**
     * @notice Test if the owner can successfully call createRaise.
     */
    function test_Owner_Can_CreateRaise() public {
        vm.prank(owner); // Ensure the call is made by the owner
        address newRaiseAddress = factory.createRaise(
            dummyToken,
            dummyAcceptedToken,
            dummyPrice,
            dummyPresaleStart,
            dummyPublicSaleStart,
            dummyEndTime,
            dummyMerkleRoot,
            projectWallet, // Owner of the specific raise
            dummyFeeRecipient,
            dummyFeeBps,
            dummyMaxRaise,
            dummyMinAlloc,
            dummyMaxAlloc
        );
        assertTrue(newRaiseAddress != address(0), "createRaise should return a non-zero address");
        // Further checks: Does deployedRaises array contain the address?
        assertEq(factory.deployedRaises(0), newRaiseAddress, "New raise address should be in deployedRaises array");
        assertEq(factory.deployedRaisesCount(), 1, "Deployed raises count should be 1");
    }

    /**
     * @notice Test if a non-owner fails to call createRaise.
     * We expect this call to revert.
     */
    function test_Fail_NonOwner_Cannot_CreateRaise() public {
        vm.prank(user1); // Make the call from a non-owner address
        // Expect the revert with the specific address of the unauthorized caller
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1)); 
        factory.createRaise(
            dummyToken,
            dummyAcceptedToken,
            dummyPrice,
            dummyPresaleStart,
            dummyPublicSaleStart,
            dummyEndTime,
            dummyMerkleRoot,
            projectWallet,
            dummyFeeRecipient,
            dummyFeeBps,
            dummyMaxRaise,
            dummyMinAlloc,
            dummyMaxAlloc
        );
    }

    /**
     * @notice Test if createRaise emits the correct RaiseCreated event.
     */
    function test_CreateRaise_EmitsEvent() public {
        vm.prank(owner);

        // Expect the RaiseCreated event
        // Check indexed parameters first (newRaiseAddress, owner)
        // Then check non-indexed parameters (token, acceptedToken, pricePerToken)
        // checkTopic1=false (don't check address exactly), checkTopic2=true (check owner), checkTopic3=false (none), checkData=true
        vm.expectEmit(false, true, false, true);
        emit CradleFactory.RaiseCreated(
            address(0), // Placeholder ignored since checkTopic1 is false
            projectWallet, // The _raiseOwner parameter passed (checked)
            dummyToken, // Checked in data
            dummyAcceptedToken, // Checked in data
            dummyPrice // Checked in data
        );
        
        // Execute the function that should emit the event (removed unused variable)
        factory.createRaise(
            dummyToken,
            dummyAcceptedToken,
            dummyPrice,
            dummyPresaleStart,
            dummyPublicSaleStart,
            dummyEndTime,
            dummyMerkleRoot,
            projectWallet, 
            dummyFeeRecipient,
            dummyFeeBps,
            dummyMaxRaise,
            dummyMinAlloc,
            dummyMaxAlloc
        );
        
        // Optional: Further check on the emitted address if needed, but vm.expectEmit handles the structure.
        // You could potentially capture the logs if vm.expectEmit felt insufficient.
    }

    /**
     * @notice Test if getDeployedRaises returns the correct list after multiple deployments.
     */
    function test_GetDeployedRaises_ReturnsCorrectList() public {
        // Deploy first raise
        vm.prank(owner);
        address raise1 = factory.createRaise(dummyToken, dummyAcceptedToken, dummyPrice, dummyPresaleStart, dummyPublicSaleStart, dummyEndTime, dummyMerkleRoot, projectWallet, dummyFeeRecipient, dummyFeeBps, dummyMaxRaise, dummyMinAlloc, dummyMaxAlloc);

        // Deploy second raise (can vary parameters if needed)
        address projectWallet2 = makeAddr("projectWallet2");
        vm.prank(owner);
        address raise2 = factory.createRaise(address(0x11), address(0x22), dummyPrice+1, dummyPresaleStart, dummyPublicSaleStart, dummyEndTime, dummyMerkleRoot, projectWallet2, dummyFeeRecipient, dummyFeeBps, dummyMaxRaise, dummyMinAlloc, dummyMaxAlloc);

        // Get the list of deployed raises
        address[] memory deployed = factory.getDeployedRaises();

        // Check the length and contents
        assertEq(deployed.length, 2, "Deployed raises array should have length 2");
        assertEq(deployed[0], raise1, "First element should be the address of the first raise");
        assertEq(deployed[1], raise2, "Second element should be the address of the second raise");
    }

    // --- TODO: More Test Functions ---
    // test_Fail_CreateRaise_WithZeroAddressOwner() // Add check in factory? No, CradleRaise handles.
    // ... other edge cases for parameters ...

} 