// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TachyonToken.sol";
import "../src/GreenVerifier.sol";
import "../src/AIOracle.sol";
import "../src/NodeRegistry.sol";
import "../src/RewardManager.sol";
import "../src/JobManager.sol";

contract TachyonSystemTest is Test {
    // Contract instances
    TachyonToken public tachyonToken;
    GreenVerifier public greenVerifier;
    AIOracle public aiOracle;
    NodeRegistry public nodeRegistry;
    RewardManager public rewardManager;
    JobManager public jobManager;

    // Test addresses
    address public owner = address(0x1);
    address public node1 = address(0x2);
    address public node2 = address(0x3);
    address public client = address(0x4);
    address public energyProvider = address(0x5);

    // Mock addresses for external dependencies
    address public mockLink = address(0x100);
    address public mockOracle = address(0x101);
    address public mockZkVerifier = address(0x102);
    bytes32 public mockJobId = bytes32("mockJobId");
    uint256 public mockFee = 0.1 * 10 ** 18;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy all contracts with UUPS proxies
        deploySystemContracts();

        // Setup roles and permissions
        setupRolesAndPermissions();

        // Setup test data
        setupTestData();

        vm.stopPrank();
    }

    function deploySystemContracts() internal {
        // 1. Deploy TachyonToken
        TachyonToken tachyonImpl = new TachyonToken();
        bytes memory tachyonInitData = abi.encodeWithSelector(TachyonToken.initialize.selector, owner);
        ERC1967Proxy tachyonProxy = new ERC1967Proxy(address(tachyonImpl), tachyonInitData);
        tachyonToken = TachyonToken(payable(address(tachyonProxy)));

        // 2. Deploy GreenVerifier
        GreenVerifier greenImpl = new GreenVerifier();
        bytes memory greenInitData = abi.encodeWithSelector(GreenVerifier.initialize.selector, owner);
        ERC1967Proxy greenProxy = new ERC1967Proxy(address(greenImpl), greenInitData);
        greenVerifier = GreenVerifier(address(greenProxy));

        // 3. Deploy AIOracle
        AIOracle aiImpl = new AIOracle();
        bytes memory aiInitData =
            abi.encodeWithSelector(AIOracle.initialize.selector, mockLink, mockOracle, mockJobId, mockFee, owner);
        ERC1967Proxy aiProxy = new ERC1967Proxy(address(aiImpl), aiInitData);
        aiOracle = AIOracle(address(aiProxy));

        // 4. Deploy NodeRegistry
        NodeRegistry nodeImpl = new NodeRegistry();
        bytes memory nodeInitData = abi.encodeWithSelector(
            NodeRegistry.initialize.selector, address(tachyonToken), address(greenVerifier), address(aiOracle), owner
        );
        ERC1967Proxy nodeProxy = new ERC1967Proxy(address(nodeImpl), nodeInitData);
        nodeRegistry = NodeRegistry(address(nodeProxy));

        // 5. Deploy RewardManager
        RewardManager rewardImpl = new RewardManager();
        bytes memory rewardInitData = abi.encodeWithSelector(
            RewardManager.initialize.selector,
            address(tachyonToken),
            address(greenVerifier),
            address(aiOracle),
            mockZkVerifier,
            owner
        );
        ERC1967Proxy rewardProxy = new ERC1967Proxy(address(rewardImpl), rewardInitData);
        rewardManager = RewardManager(address(rewardProxy));

        // 6. Deploy JobManager
        JobManager jobImpl = new JobManager();
        bytes memory jobInitData = abi.encodeWithSelector(
            JobManager.initialize.selector,
            address(tachyonToken),
            address(nodeRegistry),
            address(aiOracle),
            address(greenVerifier),
            owner
        );
        ERC1967Proxy jobProxy = new ERC1967Proxy(address(jobImpl), jobInitData);
        jobManager = JobManager(address(jobProxy));
    }

    function setupRolesAndPermissions() internal {
        // Grant MINTER_ROLE to RewardManager
        tachyonToken.grantRole(tachyonToken.MINTER_ROLE(), address(rewardManager));

        // Grant AI_CONSUMER_ROLE to JobManager and NodeRegistry
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), address(jobManager));
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), address(nodeRegistry));

        // Grant SLASHER_ROLE to RewardManager
        nodeRegistry.grantRole(nodeRegistry.SLASHER_ROLE(), address(rewardManager));

        // Grant ORACLE_ROLE to energy provider
        greenVerifier.grantRole(greenVerifier.ORACLE_ROLE(), energyProvider);

        // Grant JOB_CREATOR_ROLE to client
        jobManager.grantRole(jobManager.JOB_CREATOR_ROLE(), client);
    }

    function setupTestData() internal {
        // Mint tokens for testing
        tachyonToken.mint(node1, 10000 * 10 ** 18);
        tachyonToken.mint(node2, 10000 * 10 ** 18);
        tachyonToken.mint(client, 1000 * 10 ** 18);

        // Setup AI scores for nodes
        aiOracle.updateNodeScore(node1, 85);
        aiOracle.updateNodeScore(node2, 70);
    }

    // === Core Functionality Tests ===

    function testTokenInitialization() public {
        assertEq(tachyonToken.name(), "Tachyon Token");
        assertEq(tachyonToken.symbol(), "TACH");
        // Total supply includes initial 10B + minted test tokens (21K)
        assertEq(tachyonToken.totalSupply(), (10_000_000_000 + 21_000) * 10 ** 18);
        assertTrue(tachyonToken.hasRole(tachyonToken.DEFAULT_ADMIN_ROLE(), owner));
    }

    function testNodeRegistration() public {
        vm.startPrank(node1);

        // Approve tokens for staking (Gaming Rig requires 1500 TACH)
        tachyonToken.approve(address(nodeRegistry), 1500 * 10 ** 18);

        // Create node capabilities (Gaming Rig - requires 1500 TACH)
        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.GAMING_RIG,
            cpuCores: 8,
            cpuFrequencyMHz: 3800,
            ramGB: 32,
            storageGB: 2000,
            gpuMemoryGB: 16,
            gpuModel: "RTX 4090",
            hasGPU: true,
            hasTPU: false,
            bandwidth: 1000,
            uptime: 99,
            isMobile: false,
            batteryCapacityWh: 0,
            operatingSystem: "Windows 11",
            supportsContainers: true,
            supportsKubernetes: false,
            networkLatencyMs: 10,
            isDataCenterHosted: false
        });

        // Create proper signature for testing
        bytes memory attestationData = "mockAttestation";
        bytes32 messageHash = keccak256(abi.encode(node1, capabilities, attestationData));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Register node (stake amount is determined by device type)
        // Temporarily grant attestor role to test private key signer
        address signer = vm.addr(1);
        nodeRegistry.grantRole(nodeRegistry.ATTESTOR_ROLE(), signer);

        nodeRegistry.registerNode(capabilities, attestationData, signature);

        // Verify registration
        (NodeRegistry.NodeInfo memory nodeInfo,,) = nodeRegistry.getNodeDetails(node1);
        assertTrue(nodeInfo.registered);
        assertEq(nodeInfo.stake, 1000 * 10 ** 18);
        assertEq(nodeInfo.reputation, 50); // Initial reputation

        vm.stopPrank();
    }

    function testGreenEnergyVerification() public {
        // Submit green certificate as node1
        vm.startPrank(node1);

        bytes memory certificateData = "solarPanelData";
        bytes32 messageHash = keccak256(abi.encodePacked(node1, uint256(1), uint256(80), certificateData));

        // Mock signature from energy provider
        bytes memory signature = abi.encodePacked(messageHash);

        greenVerifier.submitGreenCertificate(
            1, // Solar
            80, // 80% renewable
            certificateData,
            signature
        );
        vm.stopPrank();

        // Verify certificate as energy provider
        vm.startPrank(energyProvider);
        greenVerifier.verifyCertificate(node1, true);

        // Check green status
        assertTrue(greenVerifier.isNodeGreen(node1));
        uint256 multiplier = greenVerifier.getRewardMultiplier(node1);
        assertGt(multiplier, 100); // Should be > 1x multiplier

        vm.stopPrank();
    }

    function testJobCreationWithAIOptimization() public {
        // First register a node
        registerTestNode();

        vm.startPrank(client);

        // Approve payment
        tachyonToken.approve(address(jobManager), 100 * 10 ** 18);

        // Create resource requirements
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 100,
            minBandwidthMbps: 100,
            requiresGPU: true,
            minGpuMemoryGB: 4,
            estimatedDurationMinutes: 60
        });

        // Create job
        uint256 jobId = jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.HIGH,
            requirements,
            100 * 10 ** 18,
            block.timestamp + 1 hours,
            "QmTestIPFSHash",
            true // Prefer green nodes
        );

        // Verify job creation
        (
            uint256 returnedJobId,
            address jobClient,
            JobManager.JobType jobType,
            ,
            ,
            ,
            uint256 payment,
            ,
            ,
            ,
            ,
            ,
            ,
            bool preferGreen,
            ,
        ) = jobManager.jobs(jobId);

        assertEq(returnedJobId, jobId);
        assertEq(jobClient, client);
        assertEq(uint8(jobType), uint8(JobManager.JobType.ML_INFERENCE));
        assertEq(payment, 100 * 10 ** 18);
        assertTrue(preferGreen);

        vm.stopPrank();
    }

    function testAIOptimizedJobAssignment() public {
        // Register nodes and create job
        registerTestNode();
        uint256 jobId = createTestJob();

        vm.startPrank(owner);

        // Assign job using AI optimization
        jobManager.assignJobToOptimalNode(jobId);

        // Verify job assignment
        (,,,,,,,,,,, address assignedNode,,,,) = jobManager.jobs(jobId);
        assertEq(assignedNode, node1); // Should assign to node1 (higher AI score)

        vm.stopPrank();
    }

    function testRewardDistributionWithMultipliers() public {
        // Setup: register node, set green status, create and complete job
        registerTestNode();
        setNodeGreenStatus();
        uint256 jobId = createAndAssignJob();

        vm.startPrank(node1);

        // Complete job
        jobManager.completeJob(jobId, keccak256("resultData"), "QmResultIPFSHash");

        vm.stopPrank();

        // Check that reward is calculated with multipliers
        uint256 pendingReward = rewardManager.pendingRewards(node1);
        assertGt(pendingReward, 100 * 10 ** 18); // Should be > base reward due to multipliers
    }

    function testSystemUpgradability() public {
        vm.startPrank(owner);

        // Deploy new implementation
        TachyonToken newImpl = new TachyonToken();

        // Upgrade contract
        tachyonToken.upgradeToAndCall(address(newImpl), "");

        // Verify upgrade worked
        assertEq(tachyonToken.version(), "1.0.0");

        vm.stopPrank();
    }

    function testComprehensiveAccessControl() public {
        // Test that unauthorized users cannot call restricted functions
        vm.startPrank(address(0x999));

        vm.expectRevert();
        tachyonToken.mint(address(0x999), 1000);

        vm.expectRevert();
        aiOracle.updateNodeScore(node1, 100);

        vm.expectRevert();
        greenVerifier.verifyCertificate(node1, true);

        vm.stopPrank();
    }

    function testNetworkStatistics() public {
        // Setup some data
        registerTestNode();
        createTestJob();

        // Test job statistics
        (uint256 total, uint256 completed, uint256 active, uint256 completionRate, uint256 avgGreenJobs) =
            jobManager.getJobStatistics();

        assertEq(total, 1);
        assertEq(completed, 0);
        assertEq(active, 1);
        assertEq(avgGreenJobs, 100); // 100% of jobs prefer green
    }

    function testZKProofValidation() public {
        // Mock ZK proof data
        RewardManager.ZKProof memory proof = RewardManager.ZKProof({
            a: [uint256(1), uint256(2)],
            b: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            c: [uint256(7), uint256(8)],
            publicInputs: [uint256(9), uint256(10), uint256(11), uint256(12)]
        });

        vm.startPrank(node1);

        // Submit task with ZK proof
        rewardManager.submitTaskCompletion(bytes32("testTask"), keccak256("resultHash"), proof);

        // Verify task was submitted
        (address taskNode, uint256 reward, RewardManager.ValidationStatus status, bool zkValidated) =
            rewardManager.getTaskDetails(bytes32("testTask"));

        assertEq(taskNode, node1);
        assertEq(uint8(status), uint8(RewardManager.ValidationStatus.PENDING));

        vm.stopPrank();
    }

    // === Helper Functions ===

    function registerTestNode() internal {
        vm.startPrank(node1);

        // Workstation requires 1000 TACH
        tachyonToken.approve(address(nodeRegistry), 1000 * 10 ** 18);

        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.WORKSTATION,
            cpuCores: 8,
            cpuFrequencyMHz: 3200,
            ramGB: 32,
            storageGB: 1000,
            gpuMemoryGB: 8,
            gpuModel: "RTX 3080",
            hasGPU: true,
            hasTPU: false,
            bandwidth: 1000,
            uptime: 99,
            isMobile: false,
            batteryCapacityWh: 0,
            operatingSystem: "Linux",
            supportsContainers: true,
            supportsKubernetes: true,
            networkLatencyMs: 5,
            isDataCenterHosted: false
        });

        bytes memory helperAttestationData = "mockAttestation";
        bytes32 helperMessageHash = keccak256(abi.encode(node1, capabilities, helperAttestationData));
        (uint8 helperV, bytes32 helperR, bytes32 helperS) = vm.sign(1, helperMessageHash);
        bytes memory helperSignature = abi.encodePacked(helperR, helperS, helperV);

        address helperSigner = vm.addr(1);
        nodeRegistry.grantRole(nodeRegistry.ATTESTOR_ROLE(), helperSigner);

        nodeRegistry.registerNode(capabilities, helperAttestationData, helperSignature);

        vm.stopPrank();
    }

    function setNodeGreenStatus() internal {
        vm.startPrank(energyProvider);

        bytes memory certificateData = "solarData";
        bytes32 messageHash = keccak256(abi.encodePacked(node1, uint256(1), uint256(90), certificateData));

        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(
            1, // Solar
            90, // 90% renewable
            certificateData,
            abi.encodePacked(messageHash)
        );
        vm.stopPrank();

        greenVerifier.verifyCertificate(node1, true);

        vm.stopPrank();
    }

    function createTestJob() internal returns (uint256) {
        vm.startPrank(client);

        tachyonToken.approve(address(jobManager), 100 * 10 ** 18);

        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 100,
            minBandwidthMbps: 100,
            requiresGPU: true,
            minGpuMemoryGB: 4,
            estimatedDurationMinutes: 60
        });

        uint256 jobId = jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.HIGH,
            requirements,
            100 * 10 ** 18,
            block.timestamp + 1 hours,
            "QmTestIPFSHash",
            true
        );

        vm.stopPrank();
        return jobId;
    }

    function createAndAssignJob() internal returns (uint256) {
        uint256 jobId = createTestJob();

        vm.startPrank(owner);
        jobManager.assignJobToOptimalNode(jobId);
        vm.stopPrank();

        return jobId;
    }
}
