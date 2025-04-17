// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {CradleFactory} from "../src/CradleFactory.sol";
// Import errors from CradleRaise
import {
    CradleRaise,
    // List imported errors used in tests:
    InvalidMerkleProof,
    BelowMinAllocation,
    ExceedsMaxAllocation,
    SaleNotActive,
    ExceedsHardCap,
    SaleIsFinalizedOrCancelled,
    CancellationWindowPassed,
    SaleNotEnded,
    SaleNotFinalized
} from "../src/CradleRaise.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // Import Ownable for error check
import {Vm} from "forge-std/Vm.sol"; // Import Vm for Log struct
import {MockERC20} from "../src/MockERC20.sol";

// --- Test Contract ---
contract CradleRaiseTest is Test {
    using SafeERC20 for IERC20; // Use SafeERC20 for transfers/approvals in tests

    // Contracts
    CradleFactory internal factory;
    CradleRaise internal raise;
    MockERC20 internal token; // Token being "sold" (only address/decimals needed)
    MockERC20 internal acceptedToken; // Token used for payment (e.g., USDC mock)

    // Addresses
    // Use fixed addresses for consistency, especially for Merkle tests
    address internal constant factoryOwner = address(0xFAC7);
    address internal constant projectWallet = address(0x9801);
    address internal constant feeRecipient = address(0xFEE5);
    address internal constant user1 = address(0x1111111111111111111111111111111111111111);
    address internal constant user2 = address(0x2222222222222222222222222222222222222222);
    address internal constant user3 = address(0x3333333333333333333333333333333333333333);

    // Raise Parameters (adjust as needed for tests)
    uint8 internal constant TOKEN_DECIMALS = 18;
    uint8 internal constant ACCEPTED_TOKEN_DECIMALS = 6; // e.g., USDC
    uint256 internal pricePerWholeToken = 1 * (10 ** ACCEPTED_TOKEN_DECIMALS); // Price: 1 acceptedToken per 1 whole token
    uint256 internal presaleStart;
    uint256 internal publicSaleStart;
    uint256 internal endTime;
    bytes32 internal merkleRoot = bytes32(0); // Default to no presale
    uint16 internal feeBps = 500; // 5%
    uint256 internal maxRaiseAccepted = 100_000 * (10 ** ACCEPTED_TOKEN_DECIMALS); // 100k acceptedToken
    uint256 internal minAllocToken = 100 * (10 ** TOKEN_DECIMALS); // 100 units of token
    uint256 internal maxAllocToken = 1000 * (10 ** TOKEN_DECIMALS); // 1000 units of token
    string internal dummyMetadataURI = "bafkreid5a25llee6myqfbtzs3f3rp7hzshsklonpfearloojzfdutfjaru";

    // Correct root derived from manual check in test: 0x4beda981c9d34f2dd099131be6049a1d87676d227e63f4a409ee629043314b4f
    bytes32 constant TEST_MERKLE_ROOT = 0x4beda981c9d34f2dd099131be6049a1d87676d227e63f4a409ee629043314b4f;
    bytes32[] internal proofUser2 = [bytes32(0xe2c07404b8c1df4c46226425cac68c28d27a766bbddce62309f36724839b22c0)]; // user1 leaf hash
    // An address not in the whitelist
    address internal constant nonWhitelistedUser = address(0x4444444444444444444444444444444444444444);

    /**
     * @notice Helper to deploy a raise specifically for presale testing.
     */
    function _deployPresaleRaise() internal returns (CradleRaise) {
        uint256 _presaleStart = block.timestamp + 1 hours;
        uint256 _publicSaleStart = block.timestamp + 2 hours;
        uint256 _endTime = block.timestamp + 3 hours;

        vm.prank(factoryOwner);
        address specificRaiseAddress = factory.createRaise(
            address(token),
            address(acceptedToken),
            pricePerWholeToken,
            _presaleStart,
            _publicSaleStart,
            _endTime, // Future times
            TEST_MERKLE_ROOT, // Use the pre-calculated root
            projectWallet,
            feeRecipient,
            feeBps,
            maxRaiseAccepted,
            minAllocToken,
            maxAllocToken,
            dummyMetadataURI
        );
        CradleRaise presaleRaise = CradleRaise(payable(specificRaiseAddress));

        // Approve this new instance for users
        vm.startPrank(user1);
        acceptedToken.approve(address(presaleRaise), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        acceptedToken.approve(address(presaleRaise), type(uint256).max);
        vm.stopPrank();
        // No need to approve nonWhitelistedUser if they can't contribute anyway

        return presaleRaise;
    }

    function test_PresaleContribute_Success_WithProof() public {
        // Arrange
        CradleRaise presaleRaise = _deployPresaleRaise();
        // Warp time to be within the presale window
        vm.warp(presaleRaise.presaleStart() + 1 seconds);

        uint256 amountToBuy = minAllocToken;
        uint256 expectedAccepted = (amountToBuy * pricePerWholeToken) / (10 ** TOKEN_DECIMALS);

        uint256 initialUserBalance = acceptedToken.balanceOf(user1);
        uint256 initialRaiseBalance = acceptedToken.balanceOf(address(presaleRaise));

        // Calculate leaves inside test for consistency
        bytes32 leafUser1 = keccak256(abi.encodePacked(user1));
        bytes32 leafUser2 = keccak256(abi.encodePacked(user2));
        // Check against expected values just in case
        assertEq(
            leafUser1,
            bytes32(0xe2c07404b8c1df4c46226425cac68c28d27a766bbddce62309f36724839b22c0),
            "Leaf User 1 mismatch"
        );
        assertEq(
            leafUser2,
            bytes32(0x2ab0a4443bbea3fbe4d0e1503d11ff1367842fb0c8b28a5c8550f27599a40751),
            "Leaf User 2 mismatch"
        );

        // Construct proof for user1 dynamically
        bytes32[] memory dynamicProofUser1 = new bytes32[](1);
        dynamicProofUser1[0] = leafUser2; // Proof for user1 is the hash of user2

        // Start recording logs
        vm.recordLogs();

        // Act
        vm.prank(user1);
        presaleRaise.contribute(amountToBuy, dynamicProofUser1); // Use dynamically constructed proof

        // Get recorded logs
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Assert Logs Manually
        bytes32 expectedTopic0 = keccak256("Contributed(address,uint256,uint256)");
        bytes32 expectedTopic1 = bytes32(uint256(uint160(user1))); // Address padded

        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics.length > 1 // Ensure topic1 exists
                    && entries[i].topics[0] == expectedTopic0 && entries[i].topics[1] == expectedTopic1 // Check contributor topic
                    && entries[i].emitter == address(presaleRaise)
            ) {
                (uint256 emittedTokenAmount, uint256 emittedAcceptedAmount) =
                    abi.decode(entries[i].data, (uint256, uint256));
                assertEq(emittedTokenAmount, amountToBuy, "Log Data: Token Amount Mismatch");
                assertEq(emittedAcceptedAmount, expectedAccepted, "Log Data: Accepted Amount Mismatch");
                break;
            }
            if (i == entries.length - 1) {
                fail(); // Fail unconditionally if event not found
            }
        }

        // Assert State Changes
        assertEq(
            acceptedToken.balanceOf(user1), initialUserBalance - expectedAccepted, "Presale: User balance incorrect"
        );
        assertEq(
            acceptedToken.balanceOf(address(presaleRaise)),
            initialRaiseBalance + expectedAccepted,
            "Presale: Raise balance incorrect"
        );
        assertEq(presaleRaise.contributions(user1), amountToBuy, "Presale: User contribution incorrect");
    }

    function test_Fail_PresaleContribute_NoProof() public {
        // Arrange
        CradleRaise presaleRaise = _deployPresaleRaise();
        vm.warp(presaleRaise.presaleStart() + 1 seconds);
        uint256 amountToBuy = minAllocToken;

        // Expect revert with custom error (no params)
        vm.expectRevert(InvalidMerkleProof.selector);

        // Act
        vm.prank(user1);
        presaleRaise.contribute(amountToBuy, new bytes32[](0)); // Empty proof
    }

    function test_Fail_PresaleContribute_InvalidProof() public {
        // Arrange
        CradleRaise presaleRaise = _deployPresaleRaise();
        vm.warp(presaleRaise.presaleStart() + 1 seconds);
        uint256 amountToBuy = minAllocToken;

        // Expect revert with custom error (no params)
        vm.expectRevert(InvalidMerkleProof.selector);

        // Act
        vm.prank(user1);
        presaleRaise.contribute(amountToBuy, proofUser2); // Use incorrect proof
    }

    function test_Fail_PresaleContribute_NonWhitelistedUser() public {
        // Arrange
        CradleRaise presaleRaise = _deployPresaleRaise();
        vm.warp(presaleRaise.presaleStart() + 1 seconds);
        uint256 amountToBuy = minAllocToken;

        // Expect revert with custom error (no params)
        vm.expectRevert(InvalidMerkleProof.selector);

        // Act
        vm.prank(nonWhitelistedUser);
        presaleRaise.contribute(amountToBuy, new bytes32[](0));
    }

    // TODO: Add more presale tests...
    // - test_PublicContribute_Success_WhenPresaleExists()

    // Test Setup
    function setUp() public virtual {
        console2.log("--- Starting setUp ---");

        // Ensure block.timestamp is reasonable before adding to it
        vm.warp(10 days); // Initial timestamp = 864000
        console2.log("Warped block.timestamp to:", block.timestamp);

        // 1. Deploy Mock Tokens
        console2.log("Deploying mock tokens...");
        token = new MockERC20("Test Token", "TKN", TOKEN_DECIMALS);
        acceptedToken = new MockERC20("Mock USDC", "mUSDC", ACCEPTED_TOKEN_DECIMALS);
        console2.log("Mock tokens deployed.");

        // 2. Deploy Factory
        console2.log("Deploying factory...");
        vm.prank(factoryOwner);
        factory = new CradleFactory(factoryOwner);
        console2.log("Factory deployed.");

        // 3. Set Timestamps (relative to current block)
        console2.log("Setting timestamps...");
        presaleStart = block.timestamp + 1 days; // Presale starts 1 day AFTER current time (950400)
        publicSaleStart = presaleStart + 1 days; // Public sale starts 1 day after presale (1036800)
        endTime = publicSaleStart + 7 days; // Ends 7 days after public sale start (1641600)
        console2.log("Timestamps set (presale in future).");

        // 4. Deploy CradleRaise via Factory
        console2.log("Deploying CradleRaise via factory...");
        vm.prank(factoryOwner);
        address raiseAddress = factory.createRaise(
            address(token),
            address(acceptedToken),
            pricePerWholeToken, // Pass the pre-calculated price
            presaleStart,
            publicSaleStart,
            endTime,
            merkleRoot,
            projectWallet, // Project wallet owns the raise
            feeRecipient,
            feeBps,
            maxRaiseAccepted,
            minAllocToken,
            maxAllocToken,
            dummyMetadataURI
        );
        raise = CradleRaise(payable(raiseAddress)); // Get instance of deployed raise
        console2.log("CradleRaise deployed at:", raiseAddress);

        // 5. Mint AcceptedToken to Users
        console2.log("Minting accepted tokens to users...");
        uint256 userInitialBalance = 5000 * (10 ** ACCEPTED_TOKEN_DECIMALS); // Give users 5k acceptedToken
        acceptedToken.mint(user1, userInitialBalance);
        acceptedToken.mint(user2, userInitialBalance);
        acceptedToken.mint(user3, userInitialBalance);
        console2.log("Accepted tokens minted.");

        // 6. Approve Raise Contract to spend AcceptedToken for Users
        console2.log("Approving raise contract for user1...");
        vm.startPrank(user1);
        acceptedToken.approve(address(raise), type(uint256).max);
        vm.stopPrank();
        console2.log("User1 approved.");

        console2.log("Approving raise contract for user2...");
        vm.startPrank(user2);
        acceptedToken.approve(address(raise), type(uint256).max);
        vm.stopPrank();
        console2.log("User2 approved.");

        console2.log("Approving raise contract for user3...");
        vm.startPrank(user3);
        acceptedToken.approve(address(raise), type(uint256).max);
        vm.stopPrank();
        console2.log("User3 approved.");

        // Optional: Label addresses for easier debugging in traces
        console2.log("Labeling addresses...");
        vm.label(address(token), "TokenSold");
        vm.label(address(acceptedToken), "AcceptedToken (mUSDC)");
        vm.label(address(raise), "CradleRaise");
        vm.label(factoryOwner, "FactoryOwner");
        vm.label(projectWallet, "ProjectWallet (RaiseOwner)");
        vm.label(feeRecipient, "FeeRecipient");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        console2.log("--- Finished setUp ---");
    }

    // --- Test Functions Start Here ---

    function test_InitialState() public view {
        assertEq(address(raise.token()), address(token), "Token address mismatch");
        assertEq(address(raise.acceptedToken()), address(acceptedToken), "Accepted token address mismatch");
        assertEq(raise.pricePerToken(), pricePerWholeToken, "Price mismatch");
        assertEq(raise.presaleStart(), presaleStart, "Presale start mismatch");
        assertEq(raise.publicSaleStart(), publicSaleStart, "Public sale start mismatch");
        assertEq(raise.endTime(), endTime, "End time mismatch");
        assertEq(raise.merkleRoot(), merkleRoot, "Merkle root mismatch");
        assertEq(raise.owner(), projectWallet, "Owner (project wallet) mismatch");
        assertEq(raise.feeRecipient(), feeRecipient, "Fee recipient mismatch");
        assertEq(raise.feePercentBasisPoints(), feeBps, "Fee BPS mismatch");
        assertEq(raise.maxAcceptedTokenRaise(), maxRaiseAccepted, "Max raise mismatch");
        assertEq(raise.minTokenAllocation(), minAllocToken, "Min allocation mismatch");
        assertEq(raise.maxTokenAllocation(), maxAllocToken, "Max allocation mismatch");
        assertEq(raise.totalAcceptedTokenRaised(), 0, "Initial total raised should be 0");
        assertFalse(raise.isFinalized(), "Should not be finalized initially");
    }

    // --- Contribute Tests ---

    function test_PublicContribute_Success() public {
        // Arrange
        vm.warp(publicSaleStart);
        uint256 tokenAmountToBuy = 150 * (10 ** TOKEN_DECIMALS); // Between min (100) and max (1000)
        // Calculate expected accepted token amount based on contract's logic
        uint256 expectedAcceptedToken = (tokenAmountToBuy * pricePerWholeToken) / (10 ** TOKEN_DECIMALS);

        uint256 initialUserBalance = acceptedToken.balanceOf(user1);
        uint256 initialRaiseBalance = acceptedToken.balanceOf(address(raise));
        uint256 initialTotalRaised = raise.totalAcceptedTokenRaised();
        uint256 initialContribution = raise.contributions(user1);

        // Define expected event parameters (check indexed fields)
        // event Contributed(address indexed contributor, uint256 tokenAmount, uint256 acceptedTokenAmount);
        vm.expectEmit(true, false, false, true); // Check indexed contributor, skip others, check log emitter address
        emit CradleRaise.Contributed(user1, tokenAmountToBuy, expectedAcceptedToken);

        // Act
        vm.prank(user1);
        raise.contribute(tokenAmountToBuy, new bytes32[](0)); // Empty proof for public sale

        // Assert
        // Balances
        assertEq(acceptedToken.balanceOf(user1), initialUserBalance - expectedAcceptedToken, "User balance incorrect");
        assertEq(
            acceptedToken.balanceOf(address(raise)),
            initialRaiseBalance + expectedAcceptedToken,
            "Raise balance incorrect"
        );

        // Contract State
        assertEq(raise.totalAcceptedTokenRaised(), initialTotalRaised + expectedAcceptedToken, "Total raised incorrect");
        assertEq(raise.contributions(user1), initialContribution + tokenAmountToBuy, "User contribution incorrect");
    }

    function test_Fail_Contribute_BelowMinAllocation() public {
        // Arrange
        vm.warp(publicSaleStart);
        // Calculate an amount that is exactly 1 base unit less than the minimum
        uint256 amountToBuyBelowMin = minAllocToken - 1;

        // Expect the specific revert message from CradleRaise.sol
        vm.expectRevert(abi.encodeWithSelector(BelowMinAllocation.selector, amountToBuyBelowMin, minAllocToken));

        // Act
        // user1 attempts to contribute an amount less than the minimum required
        vm.prank(user1);
        raise.contribute(amountToBuyBelowMin, new bytes32[](0)); // Empty proof for public sale

        // Assert
        // No assertions needed here, the test passes if the expected revert occurs.
    }

    function test_Fail_Contribute_AboveMaxAllocation_SingleTX() public {
        // Arrange
        vm.warp(publicSaleStart);
        // Calculate an amount that is exactly 1 base unit more than the maximum
        uint256 amountToBuyAboveMax = maxAllocToken + 1;

        // Expect the specific revert message from CradleRaise.sol
        vm.expectRevert(abi.encodeWithSelector(ExceedsMaxAllocation.selector, 0, amountToBuyAboveMax, maxAllocToken));

        // Act
        // user1 attempts to contribute an amount more than the maximum allowed in a single tx
        vm.prank(user1);
        raise.contribute(amountToBuyAboveMax, new bytes32[](0)); // Empty proof for public sale

        // Assert
        // No assertions needed here, the test passes if the expected revert occurs.
    }

    function test_Fail_Contribute_AboveMaxAllocation_CumulativeTX() public {
        // Arrange
        vm.warp(publicSaleStart);
        // Define amounts such that the first is valid, but the sum exceeds the max
        uint256 amount1 = (maxAllocToken * 60) / 100; // 60% of max, valid
        uint256 amount2 = (maxAllocToken * 60) / 100; // Another 60%, sum > max

        // Make the first contribution successfully
        vm.prank(user1);
        raise.contribute(amount1, new bytes32[](0));

        // Act & Assert
        // Expect the revert on the second contribution
        vm.expectRevert(abi.encodeWithSelector(ExceedsMaxAllocation.selector, amount1, amount2, maxAllocToken));
        vm.prank(user1);
        raise.contribute(amount2, new bytes32[](0));
    }

    function test_Fail_Contribute_BeforeStart() public {
        // Arrange
        // Ensure the timestamp is before the earliest possible start time (presaleStart)
        // Note: Our setUp already sets presaleStart relative to block.timestamp
        uint256 timeBeforeStart = presaleStart - 1 seconds;
        vm.warp(timeBeforeStart); // Warp time to just before presale starts

        uint256 validAmount = minAllocToken; // A valid amount if the sale were active

        // Expect the specific revert message
        vm.expectRevert(abi.encodeWithSelector(SaleNotActive.selector, timeBeforeStart, presaleStart, endTime));

        // Act
        vm.prank(user1);
        raise.contribute(validAmount, new bytes32[](0));

        // Assert - handled by vm.expectRevert
    }

    function test_Fail_Contribute_AfterEnd() public {
        // Arrange
        // Warp time to exactly the end time (contribution check is < endTime)
        vm.warp(endTime);

        uint256 validAmount = minAllocToken;

        // Expect the specific revert message
        vm.expectRevert(abi.encodeWithSelector(SaleNotActive.selector, endTime, presaleStart, endTime));

        // Act
        vm.prank(user1);
        raise.contribute(validAmount, new bytes32[](0));

        // Assert - handled by vm.expectRevert
    }

    function test_Fail_Contribute_ExceedsHardCap() public {
        // Arrange: Deploy a new raise with a specific low hard cap for this test
        uint256 specificMaxRaise = 150 * (10 ** ACCEPTED_TOKEN_DECIMALS); // 150 USDC
        // Use other standard parameters from setUp
        vm.prank(factoryOwner);
        address specificRaiseAddress = factory.createRaise(
            address(token),
            address(acceptedToken),
            pricePerWholeToken,
            block.timestamp, // Start immediately
            block.timestamp, // Public sale immediate
            block.timestamp + 1 days, // Short end time
            bytes32(0),
            projectWallet,
            feeRecipient,
            feeBps,
            specificMaxRaise, // Override hard cap
            minAllocToken, // Standard min/max per user
            maxAllocToken,
            dummyMetadataURI
        );
        CradleRaise specificRaise = CradleRaise(payable(specificRaiseAddress));

        // Need to approve this new raise instance for users
        vm.startPrank(user1);
        acceptedToken.approve(address(specificRaise), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        acceptedToken.approve(address(specificRaise), type(uint256).max);
        vm.stopPrank();

        // User 1 contributes 100 TKN (requires 100 USDC). Should succeed.
        // minAllocToken = 100 * 10**18
        vm.prank(user1);
        specificRaise.contribute(minAllocToken, new bytes32[](0));
        assertEq(specificRaise.totalAcceptedTokenRaised(), 100 * (10 ** ACCEPTED_TOKEN_DECIMALS));

        // Act & Assert: User 2 attempts to contribute 100 TKN (requires 100 USDC)
        // Total would be 200 USDC, exceeding the 150 USDC cap.
        vm.expectRevert(
            abi.encodeWithSelector(
                ExceedsHardCap.selector,
                100 * (10 ** ACCEPTED_TOKEN_DECIMALS),
                100 * (10 ** ACCEPTED_TOKEN_DECIMALS),
                specificMaxRaise
            )
        );
        vm.prank(user2);
        specificRaise.contribute(minAllocToken, new bytes32[](0));
    }

    // =============================================
    //             Lifecycle Tests
    // =============================================

    // --- cancelSale Tests ---

    function test_CancelSale_Success() public {
        // Arrange: Ensure time is before presaleStart
        assertTrue(block.timestamp < raise.presaleStart(), "Timestamp not before presale start");
        assertFalse(raise.isFinalized(), "Raise should not be finalized initially");
        assertFalse(raise.isCancelled(), "Raise should not be cancelled initially");

        // Expect event emission
        // event SaleCancelled(uint256 timestamp);
        vm.expectEmit(true, false, false, true); // Check emitter address only
        emit CradleRaise.SaleCancelled(block.timestamp); // Timestamp will be checked loosely by forge if not precise

        // Act
        vm.prank(projectWallet); // Call as owner
        raise.cancelSale();

        // Assert state
        assertTrue(raise.isFinalized(), "Raise should be finalized after cancellation");
        assertTrue(raise.isCancelled(), "Raise should be marked as cancelled");
    }

    function test_Fail_CancelSale_NotOwner() public {
        // Arrange: Ensure time is before presaleStart
        assertTrue(block.timestamp < raise.presaleStart(), "Timestamp not before presale start");

        // Expect Ownable's revert with the specific user address
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));

        // Act
        vm.prank(user1); // Call as non-owner
        raise.cancelSale();
    }

    function test_Fail_CancelSale_AfterStart() public {
        // Arrange: Warp time to or after presaleStart
        vm.warp(raise.presaleStart()); // Warp exactly to presale start

        // Expect revert with custom error
        // error CancellationWindowPassed(uint256 currentTime, uint256 presaleStart);
        vm.expectRevert(
            abi.encodeWithSelector(
                CancellationWindowPassed.selector,
                block.timestamp, // Current time after warp
                raise.presaleStart()
            )
        );

        // Act
        vm.prank(projectWallet); // Call as owner
        raise.cancelSale();
    }

    function test_CancelSale_PreventsContribution() public {
        // Arrange
        assertTrue(block.timestamp < raise.presaleStart(), "Timestamp not before presale start");
        vm.prank(projectWallet);
        raise.cancelSale(); // Cancel the sale

        assertTrue(raise.isFinalized(), "Raise should be finalized after cancellation");

        // Warp time to the public sale period (which should now be inactive due to cancellation)
        vm.warp(raise.publicSaleStart() + 1 seconds);

        // Expect revert because sale is finalized/cancelled
        // error SaleIsFinalizedOrCancelled();
        vm.expectRevert(SaleIsFinalizedOrCancelled.selector);

        // Act: Try to contribute
        uint256 amountToBuy = minAllocToken;
        vm.prank(user1);
        raise.contribute(amountToBuy, new bytes32[](0)); // No proof needed for public phase attempt
    }

    function test_CancelSale_PreventsSweep() public {
        // Arrange
        assertTrue(block.timestamp < raise.presaleStart(), "Timestamp not before presale start");
        vm.prank(projectWallet);
        raise.cancelSale(); // Cancel the sale

        assertTrue(raise.isFinalized(), "Raise should be finalized after cancellation");
        assertTrue(raise.isCancelled(), "Raise should be marked as cancelled");

        // Warp time past end time (doesn't really matter as it's cancelled)
        vm.warp(raise.endTime() + 1 days);

        // Expect revert because sale is cancelled
        // error SaleNotFinalized(); (Sweep checks !isFinalized || isCancelled)
        vm.expectRevert(SaleNotFinalized.selector);

        // Act: Try to sweep
        vm.prank(projectWallet);
        raise.sweep();
    }

    // --- finalizeRaise Tests ---

    function test_FinalizeRaise_Success() public {
        // Arrange: Warp time to after endTime
        vm.warp(raise.endTime() + 1 seconds);
        assertFalse(raise.isFinalized(), "Raise should not be finalized initially");

        // Expect event emission
        // event RaiseFinalized(uint256 timestamp);
        vm.expectEmit(true, false, false, true); // Check emitter address only
        emit CradleRaise.RaiseFinalized(block.timestamp);

        // Act
        vm.prank(projectWallet); // Call as owner
        raise.finalizeRaise();

        // Assert state
        assertTrue(raise.isFinalized(), "Raise should be finalized after finalizeRaise call");
        assertFalse(raise.isCancelled(), "Raise should not be marked as cancelled");
    }

    function test_Fail_FinalizeRaise_NotOwner() public {
        // Arrange: Warp time to after endTime
        vm.warp(raise.endTime() + 1 seconds);

        // Expect Ownable's revert with the specific user address
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));

        // Act
        vm.prank(user1); // Call as non-owner
        raise.finalizeRaise();
    }

    function test_Fail_FinalizeRaise_BeforeEnd() public {
        // Arrange: Ensure time is before endTime
        assertTrue(block.timestamp < raise.endTime(), "Timestamp not before end time");

        // Expect revert with custom error
        // error SaleNotEnded(uint256 currentTime, uint256 endTime);
        vm.expectRevert(abi.encodeWithSelector(SaleNotEnded.selector, block.timestamp, raise.endTime()));

        // Act
        vm.prank(projectWallet); // Call as owner
        raise.finalizeRaise();
    }

    // --- sweep Tests ---

    function test_Sweep_Success() public {
        // Arrange: Contribute some funds first
        vm.warp(raise.publicSaleStart() + 1 seconds); // Warp to public sale
        uint256 amountToBuy = minAllocToken;
        uint256 requiredAccepted = (amountToBuy * pricePerWholeToken) / (10 ** TOKEN_DECIMALS);

        vm.startPrank(user1);
        acceptedToken.approve(address(raise), requiredAccepted);
        raise.contribute(amountToBuy, new bytes32[](0));
        vm.stopPrank();

        uint256 totalRaised = raise.totalAcceptedTokenRaised();
        assertTrue(totalRaised > 0, "Should have raised funds");

        // Finalize the raise
        vm.warp(raise.endTime() + 1 seconds);
        vm.prank(projectWallet);
        raise.finalizeRaise();
        assertTrue(raise.isFinalized(), "Raise should be finalized");
        assertFalse(raise.isCancelled(), "Raise should not be cancelled");

        // Cache balances before sweep
        uint256 initialOwnerBalance = acceptedToken.balanceOf(projectWallet);
        uint256 initialFeeRecipientBalance = acceptedToken.balanceOf(feeRecipient);
        uint256 raiseBalance = acceptedToken.balanceOf(address(raise));
        assertEq(raiseBalance, totalRaised, "Raise contract balance mismatch before sweep");

        // Calculate expected amounts
        uint256 expectedFee = (totalRaised * raise.feePercentBasisPoints()) / 10000;
        uint256 expectedProjectAmount = totalRaised - expectedFee;

        // Expect event emission
        // event RaiseSwept(uint256 totalRaised, uint256 feeAmount, uint256 projectAmount);
        vm.expectEmit(true, true, true, true); // Check all data and emitter
        emit CradleRaise.RaiseSwept(totalRaised, expectedFee, expectedProjectAmount);

        // Act: Sweep as owner
        vm.prank(projectWallet);
        raise.sweep();

        // Assert balances after sweep
        assertEq(
            acceptedToken.balanceOf(projectWallet),
            initialOwnerBalance + expectedProjectAmount,
            "Owner balance incorrect after sweep"
        );
        assertEq(
            acceptedToken.balanceOf(feeRecipient),
            initialFeeRecipientBalance + expectedFee,
            "Fee recipient balance incorrect after sweep"
        );
        assertEq(acceptedToken.balanceOf(address(raise)), 0, "Raise contract should be empty after sweep");
    }

    function test_Sweep_Success_ZeroContributions() public {
        // Arrange: No contributions made

        // Finalize the raise
        vm.warp(raise.endTime() + 1 seconds);
        vm.prank(projectWallet);
        raise.finalizeRaise();
        assertTrue(raise.isFinalized(), "Raise should be finalized");
        assertFalse(raise.isCancelled(), "Raise should not be cancelled");

        uint256 totalRaised = raise.totalAcceptedTokenRaised();
        assertEq(totalRaised, 0, "Should have zero raised funds");

        // Cache balances before sweep
        uint256 initialOwnerBalance = acceptedToken.balanceOf(projectWallet);
        uint256 initialFeeRecipientBalance = acceptedToken.balanceOf(feeRecipient);
        uint256 raiseBalance = acceptedToken.balanceOf(address(raise));
        assertEq(raiseBalance, 0, "Raise contract balance should be zero before sweep");

        // Expect event emission with zero values
        vm.expectEmit(true, true, true, true); // Check all data and emitter
        emit CradleRaise.RaiseSwept(0, 0, 0);

        // Act: Sweep as owner
        vm.prank(projectWallet);
        raise.sweep();

        // Assert balances after sweep (should be unchanged)
        assertEq(acceptedToken.balanceOf(projectWallet), initialOwnerBalance, "Owner balance should be unchanged");
        assertEq(
            acceptedToken.balanceOf(feeRecipient),
            initialFeeRecipientBalance,
            "Fee recipient balance should be unchanged"
        );
        assertEq(acceptedToken.balanceOf(address(raise)), 0, "Raise contract should remain empty");
    }

    function test_Fail_Sweep_NotOwner() public {
        // Arrange: Finalize the raise first
        vm.warp(raise.endTime() + 1 seconds);
        vm.prank(projectWallet);
        raise.finalizeRaise();

        // Expect Ownable's revert with the specific user address
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));

        // Act: Try to sweep as non-owner
        vm.prank(user1);
        raise.sweep();
    }

    function test_Fail_Sweep_NotFinalized() public {
        // Arrange: Time is after end, but finalizeRaise not called
        vm.warp(raise.endTime() + 1 seconds);
        assertFalse(raise.isFinalized(), "Raise should not be finalized");

        // Expect revert with custom error
        // error SaleNotFinalized();
        vm.expectRevert(SaleNotFinalized.selector);

        // Act: Try to sweep as owner
        vm.prank(projectWallet);
        raise.sweep();
    }

    function test_Fail_Sweep_Cancelled() public {
        // Arrange: Cancel the sale first
        assertTrue(block.timestamp < raise.presaleStart(), "Timestamp not before presale start");
        vm.prank(projectWallet);
        raise.cancelSale();

        assertTrue(raise.isFinalized(), "Raise should be finalized after cancellation");
        assertTrue(raise.isCancelled(), "Raise should be marked as cancelled");

        // Warp time after end (doesn't strictly matter)
        vm.warp(raise.endTime() + 1 seconds);

        // Expect revert with custom error because isCancelled is true
        // error SaleNotFinalized();
        vm.expectRevert(SaleNotFinalized.selector);

        // Act: Try to sweep as owner
        vm.prank(projectWallet);
        raise.sweep();
    }

    // =============================================
    //             Utility Functions
    // =============================================
    /**
     * @dev Replicates the internal logic of CradleRaise._calculateRequiredAcceptedToken
     * Used to ensure test calculations exactly match contract calculations.
     */
    function calculateExpectedCost(
        uint256 _tokenAmountToBuy,
        uint8 _tokenDecimals,
        uint256 _pricePerToken // Price already scaled by accepted token decimals
    ) internal pure returns (uint256) {
        require(_tokenDecimals > 0 && _tokenDecimals <= 36, "Test Calc: Invalid token decimals");
        uint256 denominator = 10 ** _tokenDecimals;
        if (_tokenAmountToBuy == 0) {
            return 0;
        }
        require(_pricePerToken > 0, "Test Calc: Price cannot be zero");
        uint256 numerator;
        // Check for overflow before multiplication
        uint256 maxTokenAmount = type(uint256).max / _pricePerToken;
        require(_tokenAmountToBuy <= maxTokenAmount, "Test Calc: Mul overflow check failed");
        numerator = _tokenAmountToBuy * _pricePerToken;
        uint256 requiredAcceptedToken = numerator / denominator;
        // Ensure calculation result is non-zero if input amount is non-zero
        require(requiredAcceptedToken > 0, "Test Calc: Calc amount is zero");
        return requiredAcceptedToken;
    }
}
