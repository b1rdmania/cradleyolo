# Cradle Contracts

This repository contains the Solidity smart contracts for the Cradle.build V1 token launch infrastructure.

## 🧱 Overview

Cradle is envisioned as a permissionless, tokenless launchpad built for clean, fixed-price token raises, initially targeting the Sonic network. It provides smart contracts, tooling, and aims to support frontend components for transparent public token sales, integrated with Hedgey Finance for post-sale vesting.

**V1 Core Contracts:**
*   **`CradleFactory.sol`**: Deploys and manages instances of `CradleRaise` contracts.
*   **`CradleRaise.sol`**: Governs a single fixed-price token sale, handling contributions, timings, limits, fees, and fund withdrawal.

## ✅ V1.0 Achievements (as of 2025-04-02)

*   **Core Contracts Developed:** `CradleFactory` and `CradleRaise` contracts implementing the V1 specification (fixed-price sales, optional presale, limits, fees) have been written and tested.
*   **Deployment Scripts:** Foundry scripts (`DeployMocks`, `DeployFactory`, `DeployRaiseViaFactory`) created for deploying the contracts sequentially.
*   **Sonic Testnet Deployment:** Successfully deployed the full suite of contracts to the Sonic Testnet:
    *   Mock ERC20 tokens (`mTKN`, `mUSDC`)
    *   `CradleFactory`
    *   An example `CradleRaise` instance
*   **Configuration & ABIs:** Contract addresses saved to `.env`, and ABIs generated and organized in the `abis/` directory for frontend use.
*   **Repository Updated:** All code, scripts, ABIs, and deployment artifacts pushed to the GitHub repository.

## 🔧 Requirements

*   [Foundry](https://getfoundry.sh/): Smart contract development toolchain.

## ⚙️ Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/b1rdmania/cradleyolo.git
    cd cradleyolo/cradle-contracts
    ```

2.  **Install dependencies:**
    ```bash
    forge install
    ```

3.  **Configure Environment Variables:**
    *   Copy the example environment file:
        ```bash
        cp .env.example .env
        ```
    *   Edit the `.env` file and fill in the required values:
        *   `TESTNET_PRIVATE_KEY`: Your private key for deploying to Sonic Testnet (must start with `0x`). **NEVER commit this file with your private key.**
        *   Other parameters (RPC URLs, Raise parameters) can be adjusted as needed.
        *   Deployed contract addresses (`FACTORY_ADDRESS`, `TOKEN_SOLD_ADDRESS`, etc.) will be populated during the deployment steps or can be filled in manually if interacting with existing deployments.

## 🏗️ Compilation

To compile the contracts:

```bash
forge build --via-ir
```

## ✅ Testing

To run the test suite:

```bash
forge test
```

## 🚀 Deployment (Sonic Testnet)

Deployment uses Foundry scripts and requires the `.env` file to be correctly configured, especially `TESTNET_PRIVATE_KEY` and `SONIC_TESTNET_RPC_URL`.

The deployment sequence is:

1.  **Deploy Mock Tokens (Optional but needed for Testnet):**
    Creates mock ERC20 tokens for `tokenSold` and `acceptedToken` since standard testnet tokens might be scarce. Updates `.env` with their addresses.
    ```bash
    forge script script/DeployMocks.s.sol:DeployMocks --rpc-url $SONIC_TESTNET_RPC_URL --broadcast --via-ir -vvvv
    # Manually update TOKEN_SOLD_ADDRESS and ACCEPTED_TOKEN_ADDRESS in .env with output
    ```

2.  **Deploy Factory:**
    Deploys the `CradleFactory` contract. Updates `.env` with its address.
    ```bash
    forge script script/DeployFactory.s.sol:DeployFactory --rpc-url $SONIC_TESTNET_RPC_URL --broadcast --via-ir -vvvv
    # Manually update FACTORY_ADDRESS in .env with output
    ```

3.  **Deploy Raise Instance via Factory:**
    Deploys a `CradleRaise` instance using the factory and parameters from the `.env` file (ensure mock token and factory addresses are updated in `.env` first).
    ```bash
    forge script script/DeployRaiseViaFactory.s.sol:DeployRaiseViaFactory --rpc-url $SONIC_TESTNET_RPC_URL --broadcast --via-ir -vvvv
    # Manually update RAISE_ADDRESS in .env with output
    ```

*(Note: The scripts are designed to read the private key from the `TESTNET_PRIVATE_KEY` environment variable when targeting Sonic Testnet (Chain ID 57054). Do not use the `--private-key` flag with these scripts.)*

### Current Sonic Testnet Deployments (as of 2025-04-02)

*   **Mock Token Sold (`mTKN`):** `0x06726427c7326d9AB606D1E81A036D041CEcbdcD`
*   **Mock Accepted Token (`mUSDC`):** `0x1B0E3F92A3bFE3648414DC267c99b3dA59DDb7ed`
*   **Cradle Factory:** `0x8BAE780580c388f6F7eDA2d6a96D5cD6B0ebDbcF`
*   **Example Cradle Raise:** `0x60F23bF90714639D7CC6959e143faC086145B102`

*(These addresses are also reflected in the committed `.env` file, excluding the private key)*

## 📄 Contract ABIs

The Application Binary Interfaces (ABIs) for the core contracts, needed for frontend integration, can be found in the `abis/` directory:

*   `abis/CradleFactory.json`
*   `abis/CradleRaise.json`
*   `abis/MockERC20.json`

## 📝 Technical Specification (V1)

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
