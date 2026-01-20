// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Governance} from "../src/Governance.sol";
import {KLEDToken} from "../src/KLEDToken.sol";
import {StreetGovernor} from "../src/StreetGovernor.sol";
import {EditSuggestions} from "../src/EditSuggestions.sol";

// Futarchy contracts
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {FutarchyAMM} from "../src/FutarchyAMM.sol";
import {FutarchyTreasury} from "../src/FutarchyTreasury.sol";

// OpenZeppelin
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployGovernance
 * @notice Deployment script for the Governance contract
 * @dev Uses Foundry Script for deployment
 *
 * ## Usage
 *
 * ### Local deployment (Anvil):
 * ```bash
 * forge script script/Deploy.s.sol:DeployGovernance --rpc-url http://localhost:8545 --broadcast
 * ```
 *
 * ### Testnet deployment (Base Sepolia):
 * ```bash
 * forge script script/Deploy.s.sol:DeployGovernance \
 *   --rpc-url $BASE_SEPOLIA_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 * ```
 *
 * ### Mainnet deployment (Base):
 * ```bash
 * forge script script/Deploy.s.sol:DeployGovernance \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 * ```
 *
 * ## Environment Variables
 * - DEPLOYER_ADDRESS: Address that will deploy the contract
 * - OWNER_ADDRESS: Address that will own the governance contract
 * - GUARDIAN_ADDRESS: Address that can pause the contract
 * - VOTING_PERIOD: Duration of voting in seconds (default: 1 week)
 * - VOTING_DELAY: Delay before voting starts in seconds (default: 1 day)
 */
contract DeployGovernance is Script {
    // ============ Configuration ============

    /// @notice Default voting period (1 week)
    uint256 constant DEFAULT_VOTING_PERIOD = 7 days;

    /// @notice Default voting delay (1 day)
    uint256 constant DEFAULT_VOTING_DELAY = 1 days;

    // ============ Deployment ============

    /**
     * @notice Main deployment function
     * @return governance The deployed Governance contract
     */
    function run() external returns (Governance governance) {
        // Load configuration from environment
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        address guardian = vm.envOr("GUARDIAN_ADDRESS", msg.sender);
        uint256 votingPeriod = vm.envOr("VOTING_PERIOD", DEFAULT_VOTING_PERIOD);
        uint256 votingDelay = vm.envOr("VOTING_DELAY", DEFAULT_VOTING_DELAY);

        console.log("=== Governance Deployment ===");
        console.log("Deployer:", msg.sender);
        console.log("Owner:", owner);
        console.log("Guardian:", guardian);
        console.log("Voting Period:", votingPeriod);
        console.log("Voting Delay:", votingDelay);

        vm.startBroadcast();

        governance = new Governance(
            owner,
            guardian,
            votingPeriod,
            votingDelay
        );

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("Governance deployed at:", address(governance));

        // Verify deployment
        _verifyDeployment(governance, owner, guardian, votingPeriod, votingDelay);

        return governance;
    }

    /**
     * @notice Deploys to a local Anvil instance
     * @dev Uses Anvil's default private key for testing
     */
    function deployLocal() external returns (Governance governance) {
        // Anvil's default account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Local Deployment (Anvil) ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        governance = new Governance(
            deployer,    // owner
            deployer,    // guardian
            DEFAULT_VOTING_PERIOD,
            DEFAULT_VOTING_DELAY
        );

        vm.stopBroadcast();

        console.log("Governance deployed at:", address(governance));

        return governance;
    }

    /**
     * @notice Deploys to Base Sepolia testnet
     */
    function deployBaseSepolia() external returns (Governance governance) {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");

        console.log("=== Base Sepolia Deployment ===");
        console.log("Owner:", owner);
        console.log("Guardian:", guardian);

        vm.startBroadcast();

        governance = new Governance(
            owner,
            guardian,
            DEFAULT_VOTING_PERIOD,
            DEFAULT_VOTING_DELAY
        );

        vm.stopBroadcast();

        console.log("Governance deployed at:", address(governance));

        return governance;
    }

    /**
     * @notice Deploys to Base mainnet
     * @dev Use with caution - this is production deployment
     */
    function deployBaseMainnet() external returns (Governance governance) {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");

        // Production safety checks
        require(owner != address(0), "Owner address not set");
        require(guardian != address(0), "Guardian address not set");
        require(owner != guardian, "Owner and guardian should be different");

        console.log("=== Base Mainnet Deployment ===");
        console.log("WARNING: This is a production deployment!");
        console.log("Owner:", owner);
        console.log("Guardian:", guardian);

        vm.startBroadcast();

        governance = new Governance(
            owner,
            guardian,
            DEFAULT_VOTING_PERIOD,
            DEFAULT_VOTING_DELAY
        );

        vm.stopBroadcast();

        console.log("Governance deployed at:", address(governance));

        return governance;
    }

    // ============ Verification ============

    /**
     * @notice Verifies the deployment was successful
     */
    function _verifyDeployment(
        Governance governance,
        address expectedOwner,
        address expectedGuardian,
        uint256 expectedVotingPeriod,
        uint256 expectedVotingDelay
    ) internal view {
        require(address(governance) != address(0), "Deployment failed: zero address");
        require(governance.owner() == expectedOwner, "Owner mismatch");
        require(governance.guardian() == expectedGuardian, "Guardian mismatch");
        require(governance.votingPeriod() == expectedVotingPeriod, "Voting period mismatch");
        require(governance.votingDelay() == expectedVotingDelay, "Voting delay mismatch");
        require(governance.isProposer(expectedOwner), "Owner should be proposer");

        console.log("Deployment verification passed!");
    }
}

/**
 * @title DeployStreetGovernance
 * @notice Deploys the full Street Governance system (KLEDToken, StreetGovernor, EditSuggestions)
 * @dev Usage:
 *   Local: forge script script/Deploy.s.sol:DeployStreetGovernance --fork-url http://localhost:8545 --broadcast
 *   Testnet: forge script script/Deploy.s.sol:DeployStreetGovernance --rpc-url $BASE_SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployStreetGovernance is Script {
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether; // 100M KLED
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_BPS = 400; // 4%
    uint256 public constant THRESHOLD_BPS = 5000; // 50%

    function run() external returns (KLEDToken token, StreetGovernor governor, EditSuggestions editSuggestions) {
        // Use msg.sender when --private-key is passed via CLI
        address deployer = msg.sender;
        address owner = vm.envOr("OWNER", deployer);
        address guardian = vm.envOr("GUARDIAN", deployer);
        address treasury = vm.envOr("TREASURY", deployer);

        console.log("=== Street Governance Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Guardian:", guardian);
        console.log("Treasury:", treasury);

        vm.startBroadcast();

        // 1. Deploy KLED Token
        token = new KLEDToken(owner, INITIAL_SUPPLY);
        console.log("KLEDToken deployed at:", address(token));

        // 2. Deploy StreetGovernor
        governor = new StreetGovernor(
            address(token),
            owner,
            guardian,
            treasury,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_BPS,
            THRESHOLD_BPS
        );
        console.log("StreetGovernor deployed at:", address(governor));

        // 3. Deploy EditSuggestions
        editSuggestions = new EditSuggestions(
            address(token),
            address(governor),
            owner,
            treasury
        );
        console.log("EditSuggestions deployed at:", address(editSuggestions));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("KLEDToken:", address(token));
        console.log("StreetGovernor:", address(governor));
        console.log("EditSuggestions:", address(editSuggestions));
        console.log("\n=== Stake Requirements ===");
        console.log("Proposal Stake:", governor.PROPOSAL_STAKE() / 1 ether, "KLED");
        console.log("Edit Stake:", editSuggestions.EDIT_STAKE() / 1 ether, "KLED");
    }
}

/**
 * @title ConfigureGovernance
 * @notice Script for post-deployment configuration
 */
contract ConfigureGovernance is Script {
    /**
     * @notice Adds a proposer to the governance contract
     * @param governance The governance contract address
     * @param proposer The address to grant proposer role
     */
    function addProposer(address payable governance, address proposer) external {
        console.log("Adding proposer:", proposer);

        vm.startBroadcast();
        Governance(governance).setProposer(proposer, true);
        vm.stopBroadcast();

        console.log("Proposer added successfully");
    }

    /**
     * @notice Transfers ownership to a new address
     * @param governance The governance contract address
     * @param newOwner The new owner address
     */
    function transferOwnership(address payable governance, address newOwner) external {
        console.log("Transferring ownership to:", newOwner);

        vm.startBroadcast();
        Governance(governance).transferOwnership(newOwner);
        vm.stopBroadcast();

        console.log("Ownership transferred successfully");
    }
}

/**
 * @title DeployFutarchy
 * @notice Deploys Futarchy Treasury contracts for prediction market governance
 * @dev Deployment order:
 *   1. ConditionalTokens (Gnosis-style ERC1155 outcome tokens)
 *   2. FutarchyAMM (requires conditional tokens for trading)
 *   3. FutarchyTreasury (orchestrates markets, requires AMM + governor)
 *
 * Usage:
 *   Local: forge script script/Deploy.s.sol:DeployFutarchy --fork-url http://localhost:8545 --broadcast
 *   Testnet: IS_TESTNET=true forge script script/Deploy.s.sol:DeployFutarchy --rpc-url $BASE_SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast
 *
 * Environment Variables:
 *   STREET_GOVERNOR: Address of deployed StreetGovernor (required)
 *   KLED_TOKEN: Address of deployed KLEDToken (required)
 *   GUARDIAN: Address that can resolve markets for testing
 *   IS_TESTNET: true for short durations (10 min markets), false for mainnet (7 day markets)
 */
contract DeployFutarchy is Script {
    // Testnet durations (short for testing)
    uint256 constant TESTNET_MARKET_DURATION = 10 minutes;
    uint256 constant TESTNET_RESOLUTION_DELAY = 2 minutes;

    // Mainnet durations
    uint256 constant MAINNET_MARKET_DURATION = 7 days;
    uint256 constant MAINNET_RESOLUTION_DELAY = 24 hours;

    function run() external returns (
        ConditionalTokens conditionalTokens,
        FutarchyAMM futarchyAMM,
        FutarchyTreasury futarchyTreasury
    ) {
        // Load required addresses
        address kledToken = vm.envAddress("KLED_TOKEN");
        address owner = vm.envOr("OWNER", msg.sender);
        bool isTestnet = vm.envOr("IS_TESTNET", true);

        return deployFutarchy(kledToken, owner, isTestnet);
    }

    /**
     * @notice Deploy futarchy with explicit parameters (UUPS proxy pattern)
     * @param kledToken Address of the KLEDToken contract
     * @param guardian Address that will be guardian (emergency actions)
     * @param isTestnet Whether to enable test mode
     */
    function deployFutarchy(
        address kledToken,
        address guardian,
        bool isTestnet
    ) public returns (
        ConditionalTokens conditionalTokens,
        FutarchyAMM futarchyAMM,
        FutarchyTreasury futarchyTreasury
    ) {
        require(kledToken != address(0), "KLEDToken address required");

        console.log("=== Futarchy Deployment (UUPS Proxies) ===");
        console.log("KLEDToken:", kledToken);
        console.log("Guardian:", guardian);
        console.log("Is Testnet:", isTestnet);

        vm.startBroadcast();

        // Step 1: Deploy ConditionalTokens (implementation + proxy)
        console.log("\nStep 1/5: Deploying ConditionalTokens...");
        ConditionalTokens ctImpl = new ConditionalTokens();
        bytes memory ctInitData = abi.encodeWithSelector(ConditionalTokens.initialize.selector, "");
        ERC1967Proxy ctProxy = new ERC1967Proxy(address(ctImpl), ctInitData);
        conditionalTokens = ConditionalTokens(address(ctProxy));
        console.log("ConditionalTokens proxy deployed at:", address(conditionalTokens));

        // Step 2: Deploy FutarchyAMM (implementation + proxy)
        console.log("\nStep 2/5: Deploying FutarchyAMM...");
        FutarchyAMM ammImpl = new FutarchyAMM();
        bytes memory ammInitData = abi.encodeWithSelector(FutarchyAMM.initialize.selector);
        ERC1967Proxy ammProxy = new ERC1967Proxy(address(ammImpl), ammInitData);
        futarchyAMM = FutarchyAMM(address(ammProxy));
        console.log("FutarchyAMM proxy deployed at:", address(futarchyAMM));

        // Step 3: Deploy simple Treasury holding contract (for KLED)
        console.log("\nStep 3/5: Deploying Treasury Holding...");
        // For now, use a simple EOA or multisig as treasury
        address treasuryHolding = guardian; // TODO: Deploy proper treasury contract
        console.log("Treasury Holding:", treasuryHolding);

        // Step 4: Deploy FutarchyTreasury (implementation + proxy)
        console.log("\nStep 4/5: Deploying FutarchyTreasury...");
        FutarchyTreasury ftImpl = new FutarchyTreasury();
        bytes memory ftInitData = abi.encodeWithSelector(
            FutarchyTreasury.initialize.selector,
            kledToken,
            address(conditionalTokens),
            address(futarchyAMM),
            treasuryHolding,
            guardian
        );
        ERC1967Proxy ftProxy = new ERC1967Proxy(address(ftImpl), ftInitData);
        futarchyTreasury = FutarchyTreasury(address(ftProxy));
        console.log("FutarchyTreasury proxy deployed at:", address(futarchyTreasury));

        // Step 5: Configure cross-references
        console.log("\nStep 5/5: Configuring cross-references...");
        conditionalTokens.setTreasury(address(futarchyTreasury));
        futarchyAMM.setTreasury(address(futarchyTreasury));
        console.log("Treasury set on ConditionalTokens and AMM");

        // Enable test mode if requested
        if (isTestnet) {
            futarchyTreasury.setTestMode(true);
            console.log("Test mode enabled");
        }

        vm.stopBroadcast();

        console.log("\n=== Futarchy Deployment Summary ===");
        console.log("ConditionalTokens (proxy):", address(conditionalTokens));
        console.log("FutarchyAMM (proxy):", address(futarchyAMM));
        console.log("FutarchyTreasury (proxy):", address(futarchyTreasury));
        console.log("Test mode:", isTestnet);

        return (conditionalTokens, futarchyAMM, futarchyTreasury);
    }
}

/**
 * @title DeployAll
 * @notice Deploys complete Street Governance system including Futarchy
 * @dev Full deployment order:
 *   1. KLEDToken (ERC20Votes governance token)
 *   2. StreetGovernor (requires token for staking/slashing)
 *   3. EditSuggestions (requires governor + token)
 *   4. ConditionalTokens (Gnosis-style outcome tokens)
 *   5. FutarchyAMM (requires conditional tokens)
 *   6. FutarchyTreasury (requires AMM + conditional tokens + governor)
 *
 * Usage:
 *   Local: IS_TESTNET=true forge script script/Deploy.s.sol:DeployAll --fork-url http://localhost:8545 --broadcast
 *   Testnet: IS_TESTNET=true forge script script/Deploy.s.sol:DeployAll --rpc-url $BASE_SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployAll is Script {
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether; // 100M KLED
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_BPS = 400; // 4%
    uint256 public constant THRESHOLD_BPS = 5000; // 50%

    // Testnet durations
    uint256 constant TESTNET_MARKET_DURATION = 10 minutes;
    uint256 constant TESTNET_RESOLUTION_DELAY = 2 minutes;

    // Mainnet durations
    uint256 constant MAINNET_MARKET_DURATION = 7 days;
    uint256 constant MAINNET_RESOLUTION_DELAY = 24 hours;

    function run() external returns (
        KLEDToken token,
        StreetGovernor governor,
        EditSuggestions editSuggestions,
        ConditionalTokens conditionalTokens,
        FutarchyAMM futarchyAMM,
        FutarchyTreasury futarchyTreasury
    ) {
        address deployer = msg.sender;
        address owner = vm.envOr("OWNER", deployer);
        address guardian = vm.envOr("GUARDIAN", deployer);
        address treasury = vm.envOr("TREASURY", deployer);
        bool isTestnet = vm.envOr("IS_TESTNET", true);

        console.log("=== Full Street Governance + Futarchy Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Guardian:", guardian);
        console.log("Treasury:", treasury);
        console.log("Is Testnet:", isTestnet);

        vm.startBroadcast();

        // ========== GOVERNANCE CONTRACTS ==========
        console.log("\n--- Deploying Governance Contracts ---");

        // 1. Deploy KLED Token
        console.log("\n1/6: Deploying KLEDToken...");
        token = new KLEDToken(owner, INITIAL_SUPPLY);
        console.log("KLEDToken deployed at:", address(token));

        // 2. Deploy StreetGovernor
        console.log("\n2/6: Deploying StreetGovernor...");
        governor = new StreetGovernor(
            address(token),
            owner,
            guardian,
            treasury,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_BPS,
            THRESHOLD_BPS
        );
        console.log("StreetGovernor deployed at:", address(governor));

        // 3. Deploy EditSuggestions
        console.log("\n3/6: Deploying EditSuggestions...");
        editSuggestions = new EditSuggestions(
            address(token),
            address(governor),
            owner,
            treasury
        );
        console.log("EditSuggestions deployed at:", address(editSuggestions));

        // ========== FUTARCHY CONTRACTS (UUPS Proxies) ==========
        console.log("\n--- Deploying Futarchy Contracts (UUPS Proxies) ---");

        // 4. Deploy ConditionalTokens (implementation + proxy)
        console.log("\n4/6: Deploying ConditionalTokens...");
        ConditionalTokens ctImpl = new ConditionalTokens();
        bytes memory ctInitData = abi.encodeWithSelector(ConditionalTokens.initialize.selector, "");
        ERC1967Proxy ctProxy = new ERC1967Proxy(address(ctImpl), ctInitData);
        conditionalTokens = ConditionalTokens(address(ctProxy));
        console.log("ConditionalTokens proxy deployed at:", address(conditionalTokens));

        // 5. Deploy FutarchyAMM (implementation + proxy)
        console.log("\n5/6: Deploying FutarchyAMM...");
        FutarchyAMM ammImpl = new FutarchyAMM();
        bytes memory ammInitData = abi.encodeWithSelector(FutarchyAMM.initialize.selector);
        ERC1967Proxy ammProxy = new ERC1967Proxy(address(ammImpl), ammInitData);
        futarchyAMM = FutarchyAMM(address(ammProxy));
        console.log("FutarchyAMM proxy deployed at:", address(futarchyAMM));

        // 6. Deploy FutarchyTreasury (implementation + proxy)
        console.log("\n6/6: Deploying FutarchyTreasury...");
        FutarchyTreasury ftImpl = new FutarchyTreasury();
        bytes memory ftInitData = abi.encodeWithSelector(
            FutarchyTreasury.initialize.selector,
            address(token),          // kledToken
            address(conditionalTokens),
            address(futarchyAMM),
            treasury,                // treasury holding
            guardian                 // guardian
        );
        ERC1967Proxy ftProxy = new ERC1967Proxy(address(ftImpl), ftInitData);
        futarchyTreasury = FutarchyTreasury(address(ftProxy));
        console.log("FutarchyTreasury proxy deployed at:", address(futarchyTreasury));

        // Configure cross-references
        console.log("\nConfiguring cross-references...");
        conditionalTokens.setTreasury(address(futarchyTreasury));
        futarchyAMM.setTreasury(address(futarchyTreasury));
        console.log("Treasury set on ConditionalTokens and AMM");

        // Enable test mode if requested
        if (isTestnet) {
            futarchyTreasury.setTestMode(true);
            console.log("Test mode enabled");
        }

        vm.stopBroadcast();

        // ========== DEPLOYMENT SUMMARY ==========
        console.log("\n==========================================");
        console.log("=== FULL DEPLOYMENT COMPLETE ===");
        console.log("==========================================");
        console.log("\n--- Governance Contracts ---");
        console.log("KLEDToken:", address(token));
        console.log("StreetGovernor:", address(governor));
        console.log("EditSuggestions:", address(editSuggestions));
        console.log("\n--- Futarchy Contracts ---");
        console.log("ConditionalTokens:", address(conditionalTokens));
        console.log("FutarchyAMM:", address(futarchyAMM));
        console.log("FutarchyTreasury:", address(futarchyTreasury));
        console.log("\n--- Configuration ---");
        console.log("Owner:", owner);
        console.log("Guardian:", guardian);
        console.log("Test Mode:", isTestnet);
        console.log("==========================================");

        return (token, governor, editSuggestions, conditionalTokens, futarchyAMM, futarchyTreasury);
    }
}
