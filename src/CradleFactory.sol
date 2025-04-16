// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CradleRaise.sol"; // Make sure CradleRaise.sol is in the same src/ directory
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title CradleFactory (V1)
 * @author Your Name/Org (@YourHandle)
 * @notice A factory contract for deploying instances of the `CradleRaise` contract.
 * @dev This contract allows a designated owner to deploy new fixed-price token sale contracts (`CradleRaise`)
 * and keeps a registry of all deployed instances. V1 deployment is restricted to the factory owner.
 */
contract CradleFactory is Ownable {
    // --- State Variables ---

    /**
     * @notice An array storing the addresses of all deployed `CradleRaise` contracts.
     * @dev Accessible publicly via the auto-generated getter function.
     */
    address[] public deployedRaises;

    // --- Events ---

    /**
     * @notice Emitted when a new `CradleRaise` contract is successfully deployed via the factory.
     * @param newRaiseAddress The address of the newly deployed `CradleRaise` contract.
     * @param owner The designated owner of the new `CradleRaise` instance (typically the project's wallet).
     * @param token The address of the ERC20 token being sold in the new raise.
     * @param acceptedToken The address of the ERC20 token accepted as payment.
     * @param pricePerToken The price for the raise (denominated in `acceptedToken` base units per whole `token`).
     */
    event RaiseCreated(
        address indexed newRaiseAddress,
        address indexed owner,
        address token,
        address acceptedToken,
        uint256 pricePerToken
    );

    // --- Constructor ---

    /**
     * @notice Sets the initial owner of the factory contract upon deployment.
     * @param _initialOwner The address designated as the factory owner.
     */
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    // --- External Functions ---

    /**
     * @notice Deploys a new `CradleRaise` contract instance.
     * @dev Restricted to the factory owner (`onlyOwner`). Takes all parameters required by the `CradleRaise` constructor.
     * Deploys the contract, stores its address, emits the `RaiseCreated` event, and returns the new address.
     * @param _token The ERC20 token being sold.
     * @param _acceptedToken The ERC20 token used for payment.
     * @param _pricePerToken Price (in `acceptedToken` base units per whole `token`).
     * @param _presaleStart Unix timestamp for presale start.
     * @param _publicSaleStart Unix timestamp for public sale start.
     * @param _endTime Unix timestamp for sale end.
     * @param _merkleRoot Merkle root for presale whitelist (`bytes32(0)` if none).
     * @param _raiseOwner Project wallet that will own the deployed `CradleRaise` instance.
     * @param _feeRecipient Address receiving the platform fee.
     * @param _feePercentBasisPoints Fee percentage in basis points (e.g., 500 = 5.00%).
     * @param _maxAcceptedTokenRaise Hard cap for the sale (in `acceptedToken` base units).
     * @param _minTokenAllocation Minimum purchase amount (in `token` base units).
     * @param _maxTokenAllocation Maximum total purchase amount per wallet (in `token` base units).
     * @return newRaiseAddress The address of the newly deployed `CradleRaise` contract.
     */
    function createRaise(
        address _token,
        address _acceptedToken,
        uint256 _pricePerToken,
        uint256 _presaleStart,
        uint256 _publicSaleStart,
        uint256 _endTime,
        bytes32 _merkleRoot,
        address _raiseOwner,
        address _feeRecipient,
        uint16 _feePercentBasisPoints,
        uint256 _maxAcceptedTokenRaise,
        uint256 _minTokenAllocation,
        uint256 _maxTokenAllocation
    ) external onlyOwner returns (address newRaiseAddress) {
        // Added explicit return variable name
        // Basic input validation - ensure the designated owner for the raise is not the zero address.
        // Most parameter validation happens within the CradleRaise constructor itself.
        if (_raiseOwner == address(0)) {
            revert ZeroAddressOwner();
        }

        // Deploy new instance of CradleRaise
        CradleRaise newRaise = new CradleRaise(
            _token,
            _acceptedToken,
            _pricePerToken,
            _presaleStart,
            _publicSaleStart,
            _endTime,
            _merkleRoot,
            _raiseOwner,
            _feeRecipient,
            _feePercentBasisPoints,
            _maxAcceptedTokenRaise,
            _minTokenAllocation,
            _maxTokenAllocation
        );

        // Get the address of the newly deployed contract
        newRaiseAddress = address(newRaise); // Assign to named return variable

        // Store the address in the registry
        deployedRaises.push(newRaiseAddress);

        // Emit event
        emit RaiseCreated(newRaiseAddress, _raiseOwner, _token, _acceptedToken, _pricePerToken);

        // Implicitly returns newRaiseAddress
    }

    // --- View Functions ---

    /**
     * @notice Returns the list of all deployed `CradleRaise` contract addresses.
     * @return An array of addresses (`address[] memory`).
     */
    function getDeployedRaises() external view returns (address[] memory) {
        return deployedRaises;
    }

    /**
     * @notice Returns the total number of raises deployed by this factory.
     * @return The count of deployed raises (`uint256`).
     */
    function deployedRaisesCount() external view returns (uint256) {
        return deployedRaises.length;
    }

    // Note: Includes standard Ownable functions like owner() and transferOwnership(...)
    // These inherit NatSpec from OpenZeppelin's Ownable contract.
}
