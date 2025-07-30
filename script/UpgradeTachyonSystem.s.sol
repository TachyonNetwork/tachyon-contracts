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
    // Existing deployment addresses
    address constant TACHYON_TOKEN_PROXY = 0x2364b88237866CD8561866980bD2f12a6c14819E;

    // Chainlink configuration for Base Sepolia
    struct ChainlinkConfig {
        address linkToken;
        address oracle;
        bytes32 jobId;
        uint256 fee;
    }

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

        // Get Chainlink configuration
        ChainlinkConfig memory chainlinkConfig = getChainlinkConfig();

        // Deploy new implementations
        NewImplementations memory newImpls = deployNewImplementations();

        // Upgrade existing contracts
        ExistingContracts memory existing = getExistingContracts();
        performUpgrades(existing, newImpls, chainlinkConfig, deployer);

        // Log results
        logUpgradeResults(existing, newImpls);

        vm.stopBroadcast();
    }

    function getChainlinkConfig() internal pure returns (ChainlinkConfig memory) {
        return ChainlinkConfig({
            linkToken: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // LINK on Base Sepolia
            oracle: 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD,
            jobId: bytes32("7d80a6386ef543a3abb52817f6707e3b"),
            fee: 0.1 * 10 ** 18
        });
    }

    function getExistingContracts() internal pure returns (ExistingContracts memory) {
        return ExistingContracts({
            tachyonTokenProxy: TACHYON_TOKEN_PROXY,
            greenVerifierProxy: address(0), // Will deploy new if not exists
            aiOracleProxy: address(0),
            nodeRegistryProxy: address(0),
            rewardManagerProxy: address(0),
            jobManagerProxy: address(0)
        });
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

    function performUpgrades(
        ExistingContracts memory existing,
        NewImplementations memory newImpls,
        ChainlinkConfig memory chainlinkConfig,
        address deployer
    ) internal {
        console.log("Performing upgrades...");

        // 1. Upgrade TachyonToken (existing proxy)
        upgradeTachyonToken(existing.tachyonTokenProxy, newImpls.tachyonTokenImpl);

        // 2. Deploy missing contracts with proxies
        if (existing.greenVerifierProxy == address(0)) {
            existing.greenVerifierProxy = deployGreenVerifierProxy(newImpls.greenVerifierImpl, deployer);
        }

        if (existing.aiOracleProxy == address(0)) {
            existing.aiOracleProxy = deployAIOracleProxy(newImpls.aiOracleImpl, chainlinkConfig, deployer);
        }

        if (existing.nodeRegistryProxy == address(0)) {
            existing.nodeRegistryProxy = deployNodeRegistryProxy(
                newImpls.nodeRegistryImpl,
                existing.tachyonTokenProxy,
                existing.greenVerifierProxy,
                existing.aiOracleProxy,
                deployer
            );
        }

        if (existing.rewardManagerProxy == address(0)) {
            existing.rewardManagerProxy = deployRewardManagerProxy(
                newImpls.rewardManagerImpl,
                existing.tachyonTokenProxy,
                existing.greenVerifierProxy,
                existing.aiOracleProxy,
                deployer
            );
        }

        if (existing.jobManagerProxy == address(0)) {
            existing.jobManagerProxy = deployJobManagerProxy(
                newImpls.jobManagerImpl,
                existing.tachyonTokenProxy,
                existing.nodeRegistryProxy,
                existing.aiOracleProxy,
                existing.greenVerifierProxy,
                deployer
            );
        }

        // Grant roles between contracts
        setupContractIntegration(existing, deployer);
    }

    function upgradeTachyonToken(address proxy, address newImpl) internal {
        console.log("Upgrading TachyonToken proxy to new implementation...");
        TachyonToken tokenProxy = TachyonToken(payable(proxy));
        tokenProxy.upgradeToAndCall(newImpl, "");
        console.log("TachyonToken upgraded successfully");
    }

    function deployGreenVerifierProxy(address impl, address owner) internal returns (address) {
        bytes memory initData = abi.encodeWithSelector(GreenVerifier.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(impl, initData);
        console.log("GreenVerifier proxy deployed at:", address(proxy));
        return address(proxy);
    }

    function deployAIOracleProxy(address impl, ChainlinkConfig memory config, address owner)
        internal
        returns (address)
    {
        bytes memory initData = abi.encodeWithSelector(
            AIOracle.initialize.selector, config.linkToken, config.oracle, config.jobId, config.fee, owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(impl, initData);
        console.log("AIOracle proxy deployed at:", address(proxy));
        return address(proxy);
    }

    function deployNodeRegistryProxy(
        address impl,
        address tachyonToken,
        address greenVerifier,
        address aiOracle,
        address owner
    ) internal returns (address) {
        bytes memory initData =
            abi.encodeWithSelector(NodeRegistry.initialize.selector, tachyonToken, greenVerifier, aiOracle, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(impl, initData);
        console.log("NodeRegistry proxy deployed at:", address(proxy));
        return address(proxy);
    }

    function deployRewardManagerProxy(
        address impl,
        address tachyonToken,
        address greenVerifier,
        address aiOracle,
        address owner
    ) internal returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            RewardManager.initialize.selector,
            tachyonToken,
            greenVerifier,
            aiOracle,
            address(0), // zkVerifier - placeholder
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(impl, initData);
        console.log("RewardManager proxy deployed at:", address(proxy));
        return address(proxy);
    }

    function deployJobManagerProxy(
        address impl,
        address tachyonToken,
        address nodeRegistry,
        address aiOracle,
        address greenVerifier,
        address owner
    ) internal returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            JobManager.initialize.selector, tachyonToken, nodeRegistry, aiOracle, greenVerifier, owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(impl, initData);
        console.log("JobManager proxy deployed at:", address(proxy));
        return address(proxy);
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
