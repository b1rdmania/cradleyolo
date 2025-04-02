
# Cradle.build - V1 Technical Specification

**Document Version:** 1.1
**Date:** 2025-04-02

## 🧱 Cradle.build — Sonic-Native Token Launch Infrastructure

Cradle is envisioned as a permissionless, tokenless launchpad built for clean, fixed-price token raises on the Sonic network. It provides smart contracts, tooling, and frontend components to launch transparent public token sales—integrated with Hedgey Finance for post-sale vesting.

## 🔒 Guiding Principles

Cradle aims to be a neutral infrastructure provider. It does not hold user funds (post-sweep), offer investment advice, or issue its own platform token. Responsibility for project quality and outcomes rests with the project teams using the platform.

## 🚀 V1 MVP Overview

**Goal:** Enable teams to launch Sonic-native token sales via a factory contract with the following core features:

* Fixed-price ERC20 contributions (e.g., USDC).
* Optional whitelist-based presale phase using a Merkle root.
* Standard public raise phase following the presale (or as the only phase).
* Configurable fee routing (e.g., 5% = 500 basis points suggested default) on withdrawal.
* Exportable allocations for post-raise vesting (via Hedgey).
* Enforceable Minimum and Maximum contribution limits per wallet (denominated in the `token` being sold).
* Owner-controlled ability to cancel the sale *before* it starts.
* Deployment of individual sale contracts via a central `CradleFactory` contract (owner-controlled for V1).

## 🧱 Smart Contracts (V1)

### 1. `CradleRaise.sol`

* **Description:** Immutable smart contract governing a single token sale instance. Stores sale configuration, manages contribution phases, tracks contributions, enforces hard caps and per-wallet limits, and facilitates fund withdrawal with fee application. Includes a pre-start cancellation mechanism.
* *(Note: Uses dynamic decimal fetching via `IERC20Metadata` for robust calculations involving the token being sold.)*
* **Constructor Parameters:**
    * `address _token`: The ERC20 token being sold.
    * `address _acceptedToken`: The ERC20 token used for payment (e.g., USDC on Sonic).
    * `uint256 _pricePerToken`: Price defined as the amount of `acceptedToken` base units required per 1 *whole* `token` (e.g., 1e18 base units). Must be pre-calculated correctly by deployer/UI based on desired price and `acceptedToken` decimals.
    * `uint256 _presaleStart`: Unix timestamp for presale start.
    * `uint256 _publicSaleStart`: Unix timestamp for public sale start (must be >= presaleStart).
    * `uint256 _endTime`: Unix timestamp for sale end (must be >= publicSaleStart).
    * `bytes32 _merkleRoot`: Merkle root for presale whitelist (provide `bytes32(0)` if no presale).
    * `address _owner`: The project\'s wallet address receiving net funds after fee. Set as the contract owner.
    * `address _feeRecipient`: Address receiving the platform fee.
    * `uint16 _feePercentBasisPoints`: Fee percentage in basis points (e.g., 500 = 5.00%). Max 10000.
    * `uint256 _maxAcceptedTokenRaise`: The hard cap for the sale, denominated in `acceptedToken` base units.
    * `uint256 _minTokenAllocation`: Minimum purchase amount in **base units** of the `token` being sold allowed per contribution transaction. Must be > 0.
    * `uint256 _maxTokenAllocation`: Maximum total purchase amount in **base units** of the `token` being sold allowed per contributor wallet. Must be >= `_minTokenAllocation`.
* **Key Functions:**
    * `contribute(uint256 _tokenAmountToBuy, bytes32[] calldata _proof)`: Allows users to contribute; verifies phase, time, whitelist (if applicable), min/max limits, and hard cap. Requires prior `acceptedToken` approval.
    * `finalizeRaise()`: Owner callable after `endTime` to formally mark the sale as finalized (if not cancelled).
    * `sweep()`: Owner callable after finalization; transfers `acceptedToken` funds to `owner` and `feeRecipient`.
    * `getContribution(address _account)`: View function returning the total amount of `token` purchased by an account (in base units).
    * `cancelSale()`: Owner callable *only before* `presaleStart` to irreversibly cancel the sale.
* **Security:** Inherits `Ownable`, `ReentrancyGuard`. Uses `SafeERC20`. Implements Merkle proof verification. State locked after finalization or cancellation.
* **Custom Errors:** Uses custom errors (defined in the source file) for gas efficiency and clearer revert reasons instead of require strings.

### 2. `CradleFactory.sol`

* **Description:** A factory contract used to deploy new `CradleRaise` instances. Maintains a registry of deployed raises.
* **Key Functions:**
    * `createRaise(...)`: Deploys a new `CradleRaise` instance with the specified parameters. Restricted to the factory owner.
    * `getDeployedRaises()`: View function returning an array of all deployed raise addresses.
    * `deployedRaisesCount()`: View function returning the count of deployed raises.
* **Security:** Inherits `Ownable`.

*(See the source files in `src/` for full implementation details and NatSpec comments.)*

## Project Structure
