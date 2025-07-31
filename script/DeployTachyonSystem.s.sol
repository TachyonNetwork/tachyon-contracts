// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TachyonToken.sol";
import "../src/GreenVerifier.sol";
import "../src/AIOracle.sol";
import "../src/NodeRegistry.sol";
import "../src/RewardManager.sol";
import "../src/JobManager.sol";

// @title DeployTachyonSystem
// @notice Comprehensive deployment script for all Tachyon Network contracts
// @dev Consensys best practices: UUPS proxy deployment with proper initialization
//      Deploys all contracts with upgradeable proxies in correct dependency order
contract DeployTachyonSystem is Script {
    // Deployment configuration
    struct DeploymentConfig {
        address initialOwner;
        address chainlinkToken;
        address chainlinkOracle;
        bytes32 chainlinkJobId;
        uint256 chainlinkFee;
        address zkVerifier; // Placeholder for ZK verifier implementation
    }

    // Deployed contract addresses
    struct DeployedContracts {
        address tachyonTokenProxy;
        address tachyonTokenImpl;
        address greenVerifierProxy;
        address greenVerifierImpl;
        address aiOracleProxy;
        address aiOracleImpl;
        address nodeRegistryProxy;
        address nodeRegistryImpl;
        address rewardManagerProxy;
        address rewardManagerImpl;
        address jobManagerProxy;
        address jobManagerImpl;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Configuration for Base Sepolia
        DeploymentConfig memory config = DeploymentConfig({
            initialOwner: deployer,
            chainlinkToken: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // Base Sepolia LINK
            chainlinkOracle: 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD, // Base Sepolia Oracle
            chainlinkJobId: bytes32("7d80a6386ef543a3abb52817f6707e3b"), // Example job ID
            chainlinkFee: 0.1 * 10 ** 18, // 0.1 LINK
            zkVerifier: address(0) // Placeholder - will be deployed separately
        });

        DeployedContracts memory contracts = deployAllContracts(config);

        // Initialize cross-contract dependencies
        initializeContractDependencies(contracts, config);

        // Log deployment results
        logDeploymentResults(contracts);

        vm.stopBroadcast();
    }

    function deployAllContracts(DeploymentConfig memory config) internal returns (DeployedContracts memory contracts) {
        console.log("=== Deploying Tachyon Network System ===");

        // 1. Deploy TachyonToken
        console.log("Deploying TachyonToken...");
        TachyonToken tachyonImpl = new TachyonToken();
        contracts.tachyonTokenImpl = address(tachyonImpl);

        bytes memory tachyonInitData = abi.encodeWithSelector(TachyonToken.initialize.selector, config.initialOwner);

        ERC1967Proxy tachyonProxy = new ERC1967Proxy(address(tachyonImpl), tachyonInitData);
        contracts.tachyonTokenProxy = address(tachyonProxy);

        // 2. Deploy GreenVerifier
        console.log("Deploying GreenVerifier...");
        GreenVerifier greenImpl = new GreenVerifier();
        contracts.greenVerifierImpl = address(greenImpl);

        bytes memory greenInitData = abi.encodeWithSelector(GreenVerifier.initialize.selector, config.initialOwner);

        ERC1967Proxy greenProxy = new ERC1967Proxy(address(greenImpl), greenInitData);
        contracts.greenVerifierProxy = address(greenProxy);

        // 3. Deploy AIOracle
        console.log("Deploying AIOracle...");
        AIOracle aiImpl = new AIOracle();
        contracts.aiOracleImpl = address(aiImpl);

        bytes memory aiInitData = abi.encodeWithSelector(
            AIOracle.initialize.selector,
            config.chainlinkToken,
            config.chainlinkOracle,
            config.chainlinkJobId,
            config.chainlinkFee,
            config.initialOwner
        );

        ERC1967Proxy aiProxy = new ERC1967Proxy(address(aiImpl), aiInitData);
        contracts.aiOracleProxy = address(aiProxy);

        // 4. Deploy NodeRegistry
        console.log("Deploying NodeRegistry...");
        NodeRegistry nodeImpl = new NodeRegistry();
        contracts.nodeRegistryImpl = address(nodeImpl);

        bytes memory nodeInitData = abi.encodeWithSelector(
            NodeRegistry.initialize.selector,
            contracts.tachyonTokenProxy,
            contracts.greenVerifierProxy,
            contracts.aiOracleProxy,
            config.initialOwner
        );

        ERC1967Proxy nodeProxy = new ERC1967Proxy(address(nodeImpl), nodeInitData);
        contracts.nodeRegistryProxy = address(nodeProxy);

        // 5. Deploy RewardManager
        console.log("Deploying RewardManager...");
        RewardManager rewardImpl = new RewardManager();
        contracts.rewardManagerImpl = address(rewardImpl);

        bytes memory rewardInitData = abi.encodeWithSelector(
            RewardManager.initialize.selector,
            contracts.tachyonTokenProxy,
            contracts.greenVerifierProxy,
            contracts.aiOracleProxy,
            config.zkVerifier,
            config.initialOwner
        );

        ERC1967Proxy rewardProxy = new ERC1967Proxy(address(rewardImpl), rewardInitData);
        contracts.rewardManagerProxy = address(rewardProxy);

        // 6. Deploy JobManager
        console.log("Deploying JobManager...");
        JobManager jobImpl = new JobManager();
        contracts.jobManagerImpl = address(jobImpl);

        bytes memory jobInitData = abi.encodeWithSelector(
            JobManager.initialize.selector,
            contracts.tachyonTokenProxy,
            contracts.nodeRegistryProxy,
            contracts.aiOracleProxy,
            contracts.greenVerifierProxy,
            config.initialOwner
        );

        ERC1967Proxy jobProxy = new ERC1967Proxy(address(jobImpl), jobInitData);
        contracts.jobManagerProxy = address(jobProxy);

        return contracts;
    }

    function initializeContractDependencies(DeployedContracts memory contracts, DeploymentConfig memory config)
        internal
    {
        console.log("=== Initializing Contract Dependencies ===");

        // Grant MINTER_ROLE to RewardManager for token minting
        TachyonToken tachyonToken = TachyonToken(payable(contracts.tachyonTokenProxy));
        tachyonToken.grantRole(tachyonToken.MINTER_ROLE(), contracts.rewardManagerProxy);
        console.log("Granted MINTER_ROLE to RewardManager");

        // Grant AI_CONSUMER_ROLE to JobManager and NodeRegistry
        AIOracle aiOracle = AIOracle(contracts.aiOracleProxy);
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), contracts.jobManagerProxy);
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), contracts.nodeRegistryProxy);
        console.log("Granted AI_CONSUMER_ROLE to JobManager and NodeRegistry");

        // Grant SLASHER_ROLE to RewardManager
        NodeRegistry nodeRegistry = NodeRegistry(contracts.nodeRegistryProxy);
        nodeRegistry.grantRole(nodeRegistry.SLASHER_ROLE(), contracts.rewardManagerProxy);
        console.log("Granted SLASHER_ROLE to RewardManager");

        // Grant ORACLE_ROLE to deployer (temporary - should be energy providers)
        GreenVerifier greenVerifier = GreenVerifier(contracts.greenVerifierProxy);
        greenVerifier.grantRole(greenVerifier.ORACLE_ROLE(), config.initialOwner);
        console.log("Granted ORACLE_ROLE to deployer");

        console.log("Contract dependencies initialized successfully");
    }

    function logDeploymentResults(DeployedContracts memory contracts) internal {
        console.log("=== Deployment Results ===");
        console.log("TachyonToken Proxy:", contracts.tachyonTokenProxy);
        console.log("TachyonToken Implementation:", contracts.tachyonTokenImpl);
        console.log("GreenVerifier Proxy:", contracts.greenVerifierProxy);
        console.log("GreenVerifier Implementation:", contracts.greenVerifierImpl);
        console.log("AIOracle Proxy:", contracts.aiOracleProxy);
        console.log("AIOracle Implementation:", contracts.aiOracleImpl);
        console.log("NodeRegistry Proxy:", contracts.nodeRegistryProxy);
        console.log("NodeRegistry Implementation:", contracts.nodeRegistryImpl);
        console.log("RewardManager Proxy:", contracts.rewardManagerProxy);
        console.log("RewardManager Implementation:", contracts.rewardManagerImpl);
        console.log("JobManager Proxy:", contracts.jobManagerProxy);
        console.log("JobManager Implementation:", contracts.jobManagerImpl);

        // Comment out file writing for now due to Forge restrictions
        // The deployment addresses are logged above
    }
}
