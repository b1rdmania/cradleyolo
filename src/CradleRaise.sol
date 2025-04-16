// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // Use a recent 0.8.x version

// Import necessary OpenZeppelin contracts and libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol"; // To get decimals
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// --- Custom Errors ---

// Constructor Errors
/**
 * @dev Reverts if the `_token` or `_acceptedToken` address provided to the constructor is the zero address.
 */
error ZeroAddressToken();
/**
 * @dev Reverts if the `_owner` address provided to the constructor is the zero address.
 */
error ZeroAddressOwner();
/**
 * @dev Reverts if the `_feeRecipient` address provided to the constructor is the zero address.
 */
error ZeroAddressFeeRecipient();
/**
 * @dev Reverts if the sale timestamps are not in chronological order: `presaleStart <= publicSaleStart <= endTime`.
 * @param presaleStart The provided presale start timestamp.
 * @param publicSaleStart The provided public sale start timestamp.
 * @param endTime The provided end timestamp.
 */
error InvalidTimestamps(uint256 presaleStart, uint256 publicSaleStart, uint256 endTime);
/**
 * @dev Reverts if the `_maxAcceptedTokenRaise` (hard cap) provided to the constructor is zero.
 */
error ZeroHardCap();
/**
 * @dev Reverts if the `_pricePerToken` provided to the constructor is zero.
 */
error ZeroPrice();
/**
 * @dev Reverts if the `_feePercentBasisPoints` provided to the constructor exceeds 10000 (100%).
 * @param feePercentBasisPoints The provided fee in basis points.
 */
error FeeTooHigh(uint16 feePercentBasisPoints);
/**
 * @dev Reverts if the `_minTokenAllocation` provided to the constructor is zero.
 */
error ZeroMinAllocation();
/**
 * @dev Reverts if the `_maxTokenAllocation` is less than the `_minTokenAllocation`.
 * @param maxAlloc The provided maximum token allocation per wallet.
 * @param minAlloc The provided minimum token allocation per contribution.
 */
error MaxAllocationLessThanMin(uint256 maxAlloc, uint256 minAlloc);

// Contribution Errors
/**
 * @dev Reverts during `contribute` if the current block timestamp is outside the active sale period (`presaleStart` to `endTime`).
 * @param currentTime The current block timestamp.
 * @param startTime The sale start time (`presaleStart`).
 * @param endTime The sale end time.
 */
error SaleNotActive(uint256 currentTime, uint256 startTime, uint256 endTime);
/**
 * @dev Reverts during `contribute` if the sale has already been finalized or cancelled.
 */
error SaleIsFinalizedOrCancelled();
/**
 * @dev Reverts during `contribute` if the `_tokenAmountToBuy` is less than the configured `minTokenAllocation`.
 * @param amount The amount the user attempted to contribute.
 * @param minAmount The minimum required allocation.
 */
error BelowMinAllocation(uint256 amount, uint256 minAmount);
/**
 * @dev Reverts during `contribute` if a user tries to contribute during the presale period but no Merkle root is configured (`merkleRoot == bytes32(0)`).
 */
error PresaleNotEnabled();
/**
 * @dev Reverts during `contribute` if the provided Merkle proof is invalid for the user during the presale phase.
 */
error InvalidMerkleProof();
/**
 * @dev Reverts during `contribute` if the contribution would cause the user's total contribution to exceed the configured `maxTokenAllocation`.
 * @param currentContribution The user's current total contribution.
 * @param amountToAdd The amount the user is attempting to add.
 * @param maxAllocation The maximum allowed total contribution per user.
 */
error ExceedsMaxAllocation(uint256 currentContribution, uint256 amountToAdd, uint256 maxAllocation);
/**
 * @dev Reverts during `contribute` if the contribution would cause the `totalAcceptedTokenRaised` to exceed the `maxAcceptedTokenRaise` (hard cap).
 * @param currentTotal The current total amount raised.
 * @param amountToAdd The amount of accepted tokens this contribution would add.
 * @param hardCap The maximum allowed total raise amount.
 */
error ExceedsHardCap(uint256 currentTotal, uint256 amountToAdd, uint256 hardCap);

// Cancellation/Finalization Errors
/**
 * @dev Reverts during `cancelSale` if the function is called after the `presaleStart` time has passed.
 * @param currentTime The current block timestamp.
 * @param presaleStart The sale presale start time.
 */
error CancellationWindowPassed(uint256 currentTime, uint256 presaleStart);
/**
 * @dev Reverts during `finalizeRaise` if the function is called before the `endTime` has passed.
 * @param currentTime The current block timestamp.
 * @param endTime The sale end time.
 */
error SaleNotEnded(uint256 currentTime, uint256 endTime);
/**
 * @dev Reverts during `sweep` if the sale has not been finalized (normally, not cancelled).
 */
error SaleNotFinalized(); // Specific for sweep

// Calculation Errors
/**
 * @dev Reverts in `_calculateRequiredAcceptedToken` if fetching decimals via `IERC20Metadata.decimals()` fails or returns zero.
 * @param tokenAddress The address of the token for which decimals fetch failed.
 */
error FailedToGetTokenDecimals(address tokenAddress);
/**
 * @dev Reverts in `_calculateRequiredAcceptedToken` if the fetched `acceptedToken` decimals are zero (which would break calculations).
 * @param decimals The number of decimals returned.
 */
error InvalidTokenDecimals(uint8 decimals);
/**
 * @dev Reverts in `_calculateRequiredAcceptedToken` if the multiplication `_tokenAmountToBuy * pricePerToken` overflows.
 * @param a The first operand (`_tokenAmountToBuy`).
 * @param b The second operand (`pricePerToken`).
 */
error MultiplicationOverflow(uint256 a, uint256 b);
/**
 * @dev Reverts in `_calculateRequiredAcceptedToken` if the calculated `acceptedTokenAmount` is zero, likely due to zero `_tokenAmountToBuy`.
 * @param tokenAmountToBuy The input amount of token to buy.
 */
error ContributionCalculationZero(uint256 tokenAmountToBuy);

/**
 * @dev Reverts if the token interface is invalid.
 * @param tokenAddress The address of the token for which the interface is invalid.
 */
error InvalidTokenInterface(address tokenAddress);

/**
 * @title CradleRaise (V1)
 * @author Cradle Team (@CradleBuild)
 * @notice Implements a fixed-price token sale (raise) contract with presale and public sale phases.
 * @dev Supports ERC20 tokens for both the token being sold and the accepted payment token.
 * Features include minimum/maximum contribution limits per wallet, a Merkle root for presale whitelisting,
 * a platform fee, pre-start cancellation, and post-end finalization and fund sweeping.
 * Uses dynamic decimal handling for price calculations. Intended to be deployed via the `CradleFactory`.
 * Inherits Ownable for access control, ReentrancyGuard for security. Uses SafeERC20 for safe token transfers.
 */
contract CradleRaise is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- State Variables ---

    // Configuration (set in constructor, immutable)
    /**
     * @notice The ERC20 token being sold in this raise.
     */
    IERC20 public immutable token;
    /**
     * @notice The ERC20 token accepted as payment (e.g., USDC, WETH).
     */
    IERC20 public immutable acceptedToken;
    /**
     * @notice The price for the raise, denominated in `acceptedToken` base units per 1 *whole* `token`.
     * @dev Example: If selling TOKEN (18 decimals) for USDC (6 decimals) at $0.5 USDC per TOKEN,
     * then pricePerToken = 0.5 * 10**6 = 500,000.
     * The deployer must calculate this value based on the desired price and the `acceptedToken` decimals.
     */
    uint256 public immutable pricePerToken;
    /**
     * @notice Unix timestamp when the presale phase begins. Contributions allowed if `merkleRoot` is set.
     */
    uint256 public immutable presaleStart;
    /**
     * @notice Unix timestamp when the public sale phase begins. Contributions allowed for all.
     */
    uint256 public immutable publicSaleStart;
    /**
     * @notice Unix timestamp when the sale ends. Contributions are no longer accepted.
     */
    uint256 public immutable endTime;
    /**
     * @notice The Merkle root for the presale whitelist. If set to `bytes32(0)`, there is no presale phase.
     */
    bytes32 public immutable merkleRoot;
    /**
     * @notice The address that will receive the platform fee percentage from the raised funds.
     */
    address public immutable feeRecipient;
    /**
     * @notice The fee percentage charged on the total `acceptedToken` raised, specified in basis points.
     * @dev 1 basis point = 0.01%. E.g., 500 basis points = 5.00%. Max 10000.
     */
    uint16 public immutable feePercentBasisPoints;
    /**
     * @notice The maximum amount of `acceptedToken` that can be raised in this sale (hard cap).
     */
    uint256 public immutable maxAcceptedTokenRaise;
    /**
     * @notice The minimum amount of `token` (in base units) required for a single contribution.
     */
    uint256 public immutable minTokenAllocation;
    /**
     * @notice The maximum cumulative amount of `token` (in base units) that a single wallet can purchase throughout the sale.
     */
    uint256 public immutable maxTokenAllocation;

    // State Tracking
    /**
     * @notice The total amount of `acceptedToken` raised so far.
     */
    uint256 public totalAcceptedTokenRaised;
    /**
     * @notice Mapping from contributor address to the total amount of `token` (in base units) they have purchased.
     */
    mapping(address => uint256) public contributions;
    /**
     * @notice Flag indicating if the sale has been finalized (either normally after `endTime` or by pre-start cancellation).
     * @dev Once true, contributions and sweeping are disabled (unless sweeping after normal finalization).
     */
    bool public isFinalized;
    /**
     * @notice Flag indicating if the sale was cancelled before it started.
     * @dev This is distinct from `isFinalized` to differentiate between normal completion and cancellation.
     * If true, `isFinalized` will also be true, but sweeping funds is blocked.
     */
    bool public isCancelled; // Differentiate between cancelled and normally finalized

    // --- Events ---

    /**
     * @notice Emitted when a user successfully contributes to the sale.
     * @param contributor The address of the contributor.
     * @param tokenAmount The amount of `token` (base units) purchased in this contribution.
     * @param acceptedTokenAmount The amount of `acceptedToken` (base units) paid for this contribution.
     */
    event Contributed(address indexed contributor, uint256 tokenAmount, uint256 acceptedTokenAmount);
    /**
     * @notice Emitted when the sale is finalized normally by the owner after the `endTime`.
     */
    event RaiseFinalized(uint256 timestamp);
    /**
     * @notice Emitted when the raised funds are swept by the owner after normal finalization.
     * @param totalRaised The total amount of `acceptedToken` (base units) collected during the sale.
     * @param feeAmount The amount of `acceptedToken` (base units) transferred to the `feeRecipient`.
     * @param projectAmount The amount of `acceptedToken` (base units) transferred to the `owner`.
     */
    event RaiseSwept(uint256 totalRaised, uint256 feeAmount, uint256 projectAmount);
    /**
     * @notice Emitted when the sale is cancelled by the owner *before* the `presaleStart` time.
     */
    event SaleCancelled(uint256 timestamp);

    // --- Constructor ---

    /**
     * @notice Initializes the `CradleRaise` contract with sale parameters.
     * @dev Sets immutable configuration variables and transfers ownership to the `_owner` (project wallet).
     * Performs thorough validation on parameters using custom errors.
     * @param _token Address of the ERC20 token being sold.
     * @param _acceptedToken Address of the ERC20 token used for payment.
     * @param _pricePerToken Price in `acceptedToken` base units per whole `token` (e.g., 1 * 10**tokenDecimals base units). Must be pre-calculated based on `acceptedToken` decimals.
     * @param _presaleStart Unix timestamp for presale start.
     * @param _publicSaleStart Unix timestamp for public sale start.
     * @param _endTime Unix timestamp for sale end.
     * @param _merkleRoot Merkle root for presale whitelist (`bytes32(0)` if none).
     * @param _owner Project wallet that will own this `CradleRaise` contract and receive net funds.
     * @param _feeRecipient Address receiving the platform fee.
     * @param _feePercentBasisPoints Fee percentage in basis points (e.g., 500 = 5.00%). Max 10000.
     * @param _maxAcceptedTokenRaise Hard cap for the sale (in `acceptedToken` base units).
     * @param _minTokenAllocation Minimum purchase amount per transaction (in `token` base units). Must be > 0.
     * @param _maxTokenAllocation Maximum total purchase amount per wallet (in `token` base units). Must be >= `_minTokenAllocation`.
     */
    constructor(
        address _token,
        address _acceptedToken,
        uint256 _pricePerToken, // Must be pre-scaled by deployer based on acceptedToken decimals
        uint256 _presaleStart,
        uint256 _publicSaleStart,
        uint256 _endTime,
        bytes32 _merkleRoot,
        address _owner, // Project wallet
        address _feeRecipient,
        uint16 _feePercentBasisPoints,
        uint256 _maxAcceptedTokenRaise,
        uint256 _minTokenAllocation, // In token base units
        uint256 _maxTokenAllocation // In token base units
    ) Ownable(_owner) { // Sets the initial owner to the provided _owner address
        // --- Input Validation ---
        if (_token == address(0) || _acceptedToken == address(0)) revert ZeroAddressToken();
        if (_owner == address(0)) revert ZeroAddressOwner();
        if (_feeRecipient == address(0)) revert ZeroAddressFeeRecipient();
        // Ensure timestamps are chronological
        if (!(_publicSaleStart >= _presaleStart && _endTime >= _publicSaleStart)) revert InvalidTimestamps(_presaleStart, _publicSaleStart, _endTime);
        if (_maxAcceptedTokenRaise == 0) revert ZeroHardCap();
        if (_pricePerToken == 0) revert ZeroPrice();
        if (_feePercentBasisPoints > 10000) revert FeeTooHigh(_feePercentBasisPoints); // Max 100%
        if (_minTokenAllocation == 0) revert ZeroMinAllocation();
        if (_maxTokenAllocation < _minTokenAllocation) revert MaxAllocationLessThanMin(_maxTokenAllocation, _minTokenAllocation);

        // IERC20Metadata validation
        try IERC20Metadata(_token).decimals() returns (uint8 _decimals) {
            if (_decimals == 0) revert InvalidTokenDecimals(_decimals);
        } catch {
            revert InvalidTokenInterface(_token);
        }
        
        try IERC20Metadata(_acceptedToken).decimals() returns (uint8 _decimals) {
            if (_decimals == 0) revert InvalidTokenDecimals(_decimals);
        } catch {
            revert InvalidTokenInterface(_acceptedToken);
        }

        // --- Set Immutable State ---
        token = IERC20(_token);
        acceptedToken = IERC20(_acceptedToken);
        pricePerToken = _pricePerToken;
        presaleStart = _presaleStart;
        publicSaleStart = _publicSaleStart;
        endTime = _endTime;
        merkleRoot = _merkleRoot;
        feeRecipient = _feeRecipient;
        feePercentBasisPoints = _feePercentBasisPoints;
        maxAcceptedTokenRaise = _maxAcceptedTokenRaise;
        minTokenAllocation = _minTokenAllocation;
        maxTokenAllocation = _maxTokenAllocation;
    }

    // --- External Functions ---

    /**
     * @notice Allows users to contribute `acceptedToken` to purchase `token` during the active sale period.
     * @dev Checks sale timing, finalization/cancellation status, min/max allocation limits, presale proofs (if applicable),
     * and the hard cap. Calculates the required `acceptedToken` based on `_tokenAmountToBuy`, `pricePerToken`,
     * and dynamic token decimals. Requires the contributor to have pre-approved the contract to spend sufficient `acceptedToken`.
     * Transfers `acceptedToken` from the contributor and updates contribution records.
     * Protected against reentrancy.
     * @param _tokenAmountToBuy The amount of `token` (in base units) the user wishes to purchase. Must be >= `minTokenAllocation`.
     * @param _proof The Merkle proof required for participation during the presale phase (between `presaleStart` and `publicSaleStart`).
     * Provide an empty array `[]` if contributing during the public sale (`>= publicSaleStart`) or if no presale (`merkleRoot == 0`).
     */
    function contribute(uint256 _tokenAmountToBuy, bytes32[] calldata _proof) external nonReentrant {
        // 1. Check if sale is active and not finalized/cancelled
        uint256 currentTime = block.timestamp;
        // Sale is active between presaleStart (inclusive) and endTime (exclusive)
        if (!(currentTime >= presaleStart && currentTime < endTime)) revert SaleNotActive(currentTime, presaleStart, endTime);
        // Cannot contribute if sale is finalized (normally or cancelled)
        if (isFinalized) revert SaleIsFinalizedOrCancelled();

        // 2. Check Minimum Allocation for this contribution transaction
        if (_tokenAmountToBuy < minTokenAllocation) revert BelowMinAllocation(_tokenAmountToBuy, minTokenAllocation);

        // 3. Check phase and validate Merkle proof if in presale
        if (currentTime < publicSaleStart) { // Currently in presale phase
            if (merkleRoot == bytes32(0)) revert PresaleNotEnabled(); // Revert if presale not configured but time is before public start
            // Calculate the leaf node for the sender
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
            // Verify the proof against the stored root
            if (!MerkleProof.verify(_proof, merkleRoot, leaf)) revert InvalidMerkleProof();
        }
        // No proof needed if currentTime >= publicSaleStart (public phase)

        // 4. Check Maximum Allocation for this user (cumulative)
        uint256 currentContribution = contributions[msg.sender];
        // Calculate the user's total contribution if this one succeeds
        uint256 nextUserContribution = currentContribution + _tokenAmountToBuy;
        // Revert if this contribution would exceed the per-wallet maximum
        if (nextUserContribution > maxTokenAllocation) revert ExceedsMaxAllocation(currentContribution, _tokenAmountToBuy, maxTokenAllocation);

        // 5. Calculate required `acceptedToken` amount using dynamic decimals
        uint256 requiredAcceptedToken = _calculateRequiredAcceptedToken(_tokenAmountToBuy);

        // 6. Check against hard cap
        uint256 nextTotalRaised = totalAcceptedTokenRaised + requiredAcceptedToken;
        // Revert if this contribution would exceed the overall hard cap
        if (nextTotalRaised > maxAcceptedTokenRaise) revert ExceedsHardCap(totalAcceptedTokenRaised, requiredAcceptedToken, maxAcceptedTokenRaise);

        // --- State Updates & Interactions ---

        // 7. Update total raised and user's contribution
        totalAcceptedTokenRaised = nextTotalRaised;
        contributions[msg.sender] = nextUserContribution; // Safe due to overflow check in step 4

        // 8. Transfer `acceptedToken` from contributor to this contract
        // Requires prior approval from msg.sender
        acceptedToken.safeTransferFrom(msg.sender, address(this), requiredAcceptedToken);

        // 9. Emit event
        emit Contributed(msg.sender, _tokenAmountToBuy, requiredAcceptedToken);
    }

    /**
     * @notice Allows the owner to mark the sale as finalized after the `endTime`.
     * @dev Can only be called by the owner and only after `block.timestamp >= endTime`.
     * Sets the `isFinalized` flag to true. This is a prerequisite for calling `sweep`.
     * Does nothing if the sale was already cancelled (as `isFinalized` would already be true).
     */
    function finalizeRaise() external onlyOwner {
        // Check if the sale has actually ended
        if (block.timestamp < endTime) revert SaleNotEnded(block.timestamp, endTime);
        // If already finalized (either normally or via cancellation), do nothing further
        if (isFinalized) return;

        isFinalized = true;
        emit RaiseFinalized(block.timestamp);
    }

    /**
     * @notice Allows the owner to withdraw the collected `acceptedToken` after the sale is finalized (normally).
     * @dev Can only be called by the owner. Requires `isFinalized` to be true and `isCancelled` to be false.
     * Calculates the fee amount based on `totalAcceptedTokenRaised` and `feePercentBasisPoints`.
     * Transfers the fee amount to the `feeRecipient` and the remaining amount to the `owner`.
     * Protected against reentrancy.
     */
    function sweep() external onlyOwner nonReentrant {
        // Ensure the sale ended normally and was finalized, not cancelled
        if (!isFinalized || isCancelled) revert SaleNotFinalized();

        uint256 totalRaised = totalAcceptedTokenRaised; // Cache storage reads

        // If nothing was raised, there's nothing to sweep.
        if (totalRaised == 0) {
            emit RaiseSwept(0, 0, 0);
            return;
        }

        // Calculate fee amount (handle potential rounding down implicitly)
        uint256 feeAmount = (totalRaised * feePercentBasisPoints) / 10000;
        uint256 projectAmount = totalRaised - feeAmount; // Remainder goes to project owner

        // Transfer fee to feeRecipient
        if (feeAmount > 0) {
            acceptedToken.safeTransfer(feeRecipient, feeAmount);
        }

        // Transfer remaining funds to the project owner
        if (projectAmount > 0) {
            acceptedToken.safeTransfer(owner(), projectAmount); // owner() is from Ownable
        }

        emit RaiseSwept(totalRaised, feeAmount, projectAmount);
    }

    /**
     * @notice Allows the owner to irreversibly cancel the sale *before* it starts (`presaleStart`).
     * @dev Can only be called by the owner. Requires `block.timestamp < presaleStart`.
     * Sets both `isFinalized` and `isCancelled` flags to true, preventing contributions and sweeping.
     * Useful if the project decides not to proceed with the sale before it begins.
     */
    function cancelSale() external onlyOwner {
        // Ensure the cancellation window is still open (before presale starts)
        if (block.timestamp >= presaleStart) revert CancellationWindowPassed(block.timestamp, presaleStart);
        // Prevent cancelling multiple times or after finalization
        if (isFinalized) revert SaleIsFinalizedOrCancelled(); // Use existing error

        isFinalized = true;
        isCancelled = true; // Mark specifically as cancelled
        emit SaleCancelled(block.timestamp);
    }

    // --- View Functions ---

    /**
     * @notice Returns the total amount of `token` (in base units) purchased by a specific account.
     * @param _account The address of the contributor to query.
     * @return The total `token` amount purchased by the account.
     */
    function getContribution(address _account) external view returns (uint256) {
        return contributions[_account];
    }

    // --- Internal Functions ---

    /**
     * @notice Calculates the amount of `acceptedToken` required for a given amount of `token`.
     * @dev Fetches `acceptedToken` decimals dynamically using `IERC20Metadata`.
     * Calculation: `required = (_tokenAmountToBuy * pricePerToken) / (10**tokenDecimals)`
     * where `tokenDecimals` refers to the decimals of the `token` being sold (fetched dynamically).
     * Handles potential overflows and zero results.
     * @param _tokenAmountToBuy The amount of `token` (in base units) being purchased.
     * @return requiredAcceptedToken The calculated amount of `acceptedToken` (in base units) needed for the purchase.
     */
    function _calculateRequiredAcceptedToken(uint256 _tokenAmountToBuy) internal view returns (uint256 requiredAcceptedToken) {
        // Fetch decimals for the token being SOLD dynamically
        uint8 tokenDecimals;
        try IERC20Metadata(address(token)).decimals() returns (uint8 _decimals) {
            if (_decimals == 0) revert InvalidTokenDecimals(_decimals); // Cannot have 0 decimals for calculation
            tokenDecimals = _decimals;
        } catch {
            revert FailedToGetTokenDecimals(address(token));
        }

        // Calculate the intermediate value: amount * price
        // pricePerToken is already scaled based on acceptedToken decimals
        uint256 numerator = mul(_tokenAmountToBuy, pricePerToken);

        // Calculate the denominator: 10**tokenDecimals (scale factor for whole token)
        uint256 denominator = 10**tokenDecimals;

        // Calculate the final required amount in acceptedToken base units
        // Division truncates, which is the desired behavior here.
        requiredAcceptedToken = numerator / denominator;

        // Ensure the result is non-zero if the input amount was non-zero
        // This primarily guards against extreme price/decimal mismatches leading to zero cost.
        if (requiredAcceptedToken == 0 && _tokenAmountToBuy > 0) {
             revert ContributionCalculationZero(_tokenAmountToBuy);
        }

    }

    /**
     * @dev Internal function for checked multiplication. Reverts on overflow.
     * Included locally to avoid external library dependency solely for this,
     * although OpenZeppelin's SafeMath could also be used.
     * @param a First operand.
     * @param b Second operand.
     * @return result The product of a and b.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 result) {
        if (a == 0) {
            return 0;
        }
        result = a * b;
        if (result / a != b) {
            // Revert with a standard message or a custom error if preferred
            revert("Multiplication overflow");
        }
    }
} 