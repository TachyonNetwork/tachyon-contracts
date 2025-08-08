// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TachyonToken.sol";
import "../src/GreenVerifier.sol";
import "../src/AIOracle.sol";
import "../src/NodeRegistry.sol";
import "../src/RewardManager.sol";
import "../src/JobManager.sol";

contract UpgradeTachyonSystem is Script {
    // Chainlink configuration (optional; used only if deploying AIOracle proxy)
    struct ChainlinkConfig {
        address linkToken;
        address oracle;
        bytes32 jobId;
        uint256 fee;
    }

    // Proxies loaded from .env
    struct ExistingContracts {
        address tachyonTokenProxy;
        address greenVerifierProxy;
        address aiOracleProxy;
        address nodeRegistryProxy;
        address rewardManagerProxy;
        address jobManagerProxy;
    }

    struct NewImplementations {
        address tachyonTokenImpl;
        address greenVerifierImpl;
        address aiOracleImpl;
        address nodeRegistryImpl;
        address rewardManagerImpl;
        address jobManagerImpl;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Upgrading Tachyon System contracts...");
        console.log("Deployer address:", deployer);

        // Deploy new implementations
        NewImplementations memory newImpls = deployNewImplementations();

        // Upgrade existing contracts
        ExistingContracts memory existing = loadExistingContractsFromEnv();
        performUpgrades(existing, newImpls, deployer);

        // Log results
        logUpgradeResults(existing, newImpls);

        vm.stopBroadcast();
    }

    function loadExistingContractsFromEnv() internal returns (ExistingContracts memory c) {
        // Require proxies in .env; if any is intentionally missing, set to 0x0 in env or remove
        c.tachyonTokenProxy = vm.envAddress("TACHYON_TOKEN_PROXY");
        c.greenVerifierProxy = vm.envAddress("GREEN_VERIFIER_PROXY");
        c.aiOracleProxy = vm.envAddress("AI_ORACLE_PROXY");
        c.nodeRegistryProxy = vm.envAddress("NODE_REGISTRY_PROXY");
        c.rewardManagerProxy = vm.envAddress("REWARD_MANAGER_PROXY");
        c.jobManagerProxy = vm.envAddress("JOB_MANAGER_PROXY");
    }

    function deployNewImplementations() internal returns (NewImplementations memory impls) {
        console.log("Deploying new implementations...");

        // Deploy new implementations
        impls.tachyonTokenImpl = address(new TachyonToken());
        impls.greenVerifierImpl = address(new GreenVerifier());
        impls.aiOracleImpl = address(new AIOracle());
        impls.nodeRegistryImpl = address(new NodeRegistry());
        impls.rewardManagerImpl = address(new RewardManager());
        impls.jobManagerImpl = address(new JobManager());

        console.log("New TachyonToken implementation:", impls.tachyonTokenImpl);
        console.log("New GreenVerifier implementation:", impls.greenVerifierImpl);
        console.log("New AIOracle implementation:", impls.aiOracleImpl);
        console.log("New NodeRegistry implementation:", impls.nodeRegistryImpl);
        console.log("New RewardManager implementation:", impls.rewardManagerImpl);
        console.log("New JobManager implementation:", impls.jobManagerImpl);
    }

    function performUpgrades(ExistingContracts memory existing, NewImplementations memory newImpls, address deployer)
        internal
    {
        console.log("Performing upgrades...");

        // 1. Upgrade all existing proxies using addresses from .env
        upgradeTachyonToken(existing.tachyonTokenProxy, newImpls.tachyonTokenImpl, deployer);
        upgradeGreenVerifier(existing.greenVerifierProxy, newImpls.greenVerifierImpl, deployer);
        upgradeAIOracle(existing.aiOracleProxy, newImpls.aiOracleImpl, deployer);
        upgradeNodeRegistry(existing.nodeRegistryProxy, newImpls.nodeRegistryImpl, deployer);
        upgradeRewardManager(existing.rewardManagerProxy, newImpls.rewardManagerImpl, deployer);
        upgradeJobManager(existing.jobManagerProxy, newImpls.jobManagerImpl, deployer);

        // Grant roles between contracts
        setupContractIntegration(existing, deployer);
    }

    function upgradeTachyonToken(address proxy, address newImpl, address deployer) internal {
        console.log("Upgrading TachyonToken proxy to new implementation...");
        TachyonToken tokenProxy = TachyonToken(payable(proxy));
        require(tokenProxy.owner() == deployer, "TachyonToken: not owner");
        tokenProxy.upgradeToAndCall(newImpl, "");
        console.log("TachyonToken upgraded successfully");
    }

    function upgradeGreenVerifier(address proxy, address newImpl, address deployer) internal {
        console.log("Upgrading GreenVerifier proxy to new implementation...");
        GreenVerifier gv = GreenVerifier(proxy);
        require(gv.owner() == deployer, "GreenVerifier: not owner");
        gv.upgradeToAndCall(newImpl, "");
        console.log("GreenVerifier upgraded successfully");
    }

    function upgradeAIOracle(address proxy, address newImpl, address deployer) internal {
        console.log("Upgrading AIOracle proxy to new implementation...");
        AIOracle ai = AIOracle(proxy);
        require(ai.owner() == deployer, "AIOracle: not owner");
        ai.upgradeToAndCall(newImpl, "");
        console.log("AIOracle upgraded successfully");
    }

    function upgradeNodeRegistry(address proxy, address newImpl, address deployer) internal {
        console.log("Upgrading NodeRegistry proxy to new implementation...");
        NodeRegistry node = NodeRegistry(proxy);
        require(node.owner() == deployer, "NodeRegistry: not owner");
        node.upgradeToAndCall(newImpl, "");
        console.log("NodeRegistry upgraded successfully");
    }

    function upgradeRewardManager(address proxy, address newImpl, address deployer) internal {
        console.log("Upgrading RewardManager proxy to new implementation...");
        RewardManager rm = RewardManager(proxy);
        require(rm.owner() == deployer, "RewardManager: not owner");
        rm.upgradeToAndCall(newImpl, "");
        console.log("RewardManager upgraded successfully");
    }

    function upgradeJobManager(address proxy, address newImpl, address deployer) internal {
        console.log("Upgrading JobManager proxy to new implementation...");
        JobManager jm = JobManager(proxy);
        require(jm.owner() == deployer, "JobManager: not owner");
        jm.upgradeToAndCall(newImpl, "");
        console.log("JobManager upgraded successfully");
    }

    function setupContractIntegration(ExistingContracts memory contracts, address deployer) internal {
        console.log("Setting up contract integration...");

        // Grant MINTER_ROLE to RewardManager
        TachyonToken tachyonToken = TachyonToken(payable(contracts.tachyonTokenProxy));
        tachyonToken.grantRole(tachyonToken.MINTER_ROLE(), contracts.rewardManagerProxy);

        // Grant AI_CONSUMER_ROLE to JobManager and NodeRegistry
        AIOracle aiOracle = AIOracle(contracts.aiOracleProxy);
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), contracts.jobManagerProxy);
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), contracts.nodeRegistryProxy);

        // Ensure JobManager can manage node active task counters post-upgrade
        NodeRegistry nodeRegistry = NodeRegistry(contracts.nodeRegistryProxy);
        nodeRegistry.grantRole(nodeRegistry.TASK_MANAGER_ROLE(), contracts.jobManagerProxy);

        console.log("Contract integration setup complete");
    }

    function logUpgradeResults(ExistingContracts memory existing, NewImplementations memory newImpls) internal {
        console.log("=== Upgrade Results ===");
        console.log("TachyonToken Proxy:", existing.tachyonTokenProxy);
        console.log("TachyonToken New Implementation:", newImpls.tachyonTokenImpl);
        console.log("GreenVerifier Proxy:", existing.greenVerifierProxy);
        console.log("AIOracle Proxy:", existing.aiOracleProxy);
        console.log("NodeRegistry Proxy:", existing.nodeRegistryProxy);
        console.log("RewardManager Proxy:", existing.rewardManagerProxy);
        console.log("JobManager Proxy:", existing.jobManagerProxy);

        // Update deployments.json
        updateDeploymentsFile(existing, newImpls);
    }

    function updateDeploymentsFile(ExistingContracts memory existing, NewImplementations memory newImpls) internal {
        string memory json = string.concat(
            "{\n",
            '  "network": "base-sepolia",\n',
            '  "chainId": 84532,\n',
            '  "timestamp": "',
            vm.toString(block.timestamp),
            '",\n',
            '  "upgradeDate": "2025-07-30",\n',
            '  "contracts": {\n',
            '    "TachyonToken": {\n',
            '      "proxy": "',
            vm.toString(existing.tachyonTokenProxy),
            '",\n',
            '      "implementation": "',
            vm.toString(newImpls.tachyonTokenImpl),
            '",\n',
            '      "upgraded": true\n',
            "    },\n",
            '    "GreenVerifier": {\n',
            '      "proxy": "',
            vm.toString(existing.greenVerifierProxy),
            '",\n',
            '      "implementation": "',
            vm.toString(newImpls.greenVerifierImpl),
            '"\n',
            "    },\n",
            '    "AIOracle": {\n',
            '      "proxy": "',
            vm.toString(existing.aiOracleProxy),
            '",\n',
            '      "implementation": "',
            vm.toString(newImpls.aiOracleImpl),
            '"\n',
            "    },\n",
            '    "NodeRegistry": {\n',
            '      "proxy": "',
            vm.toString(existing.nodeRegistryProxy),
            '",\n',
            '      "implementation": "',
            vm.toString(newImpls.nodeRegistryImpl),
            '"\n',
            "    },\n",
            '    "RewardManager": {\n',
            '      "proxy": "',
            vm.toString(existing.rewardManagerProxy),
            '",\n',
            '      "implementation": "',
            vm.toString(newImpls.rewardManagerImpl),
            '"\n',
            "    },\n",
            '    "JobManager": {\n',
            '      "proxy": "',
            vm.toString(existing.jobManagerProxy),
            '",\n',
            '      "implementation": "',
            vm.toString(newImpls.jobManagerImpl),
            '"\n',
            "    }\n",
            "  }\n",
            "}"
        );

        vm.writeFile("deployments-upgraded.json", json);
        console.log("Deployment info saved to deployments-upgraded.json");
    }
}
