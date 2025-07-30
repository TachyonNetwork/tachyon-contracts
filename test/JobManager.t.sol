// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/JobManager.sol";
import "../src/TachyonToken.sol";
import "../src/NodeRegistry.sol";
import "../src/AIOracle.sol";
import "../src/GreenVerifier.sol";
import "./mocks/MockLinkToken.sol";
import "./mocks/MockOracle.sol";

contract JobManagerTest is Test {
    JobManager public jobManager;
    TachyonToken public tachyonToken;
    NodeRegistry public nodeRegistry;
    AIOracle public aiOracle;
    GreenVerifier public greenVerifier;
    MockLinkToken public mockLink;
    MockOracle public mockOracle;

    address public owner = address(0x1);
    address public client = address(0x6);

    uint256 public constant JOB_PAYMENT = 100 * 10**18;

    event JobCreated(uint256 indexed jobId, address indexed client, JobManager.JobType jobType, uint256 payment, bool preferGreen);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        mockLink = new MockLinkToken();
        mockOracle = new MockOracle();

        // Deploy TachyonToken
        TachyonToken tokenImpl = new TachyonToken();
        bytes memory tokenInitData = abi.encodeWithSelector(TachyonToken.initialize.selector, owner);
        ERC1967Proxy tokenProxy = new ERC1967Proxy(address(tokenImpl), tokenInitData);
        tachyonToken = TachyonToken(payable(address(tokenProxy)));

        // Deploy GreenVerifier
        GreenVerifier greenImpl = new GreenVerifier();
        bytes memory greenInitData = abi.encodeWithSelector(GreenVerifier.initialize.selector, owner);
        ERC1967Proxy greenProxy = new ERC1967Proxy(address(greenImpl), greenInitData);
        greenVerifier = GreenVerifier(address(greenProxy));

        // Deploy AIOracle
        AIOracle aiImpl = new AIOracle();
        bytes memory aiInitData = abi.encodeWithSelector(
            AIOracle.initialize.selector,
            address(mockLink),
            address(mockOracle),
            bytes32("test-job"),
            0.1 * 10**18,
            owner
        );
        ERC1967Proxy aiProxy = new ERC1967Proxy(address(aiImpl), aiInitData);
        aiOracle = AIOracle(address(aiProxy));

        // Deploy NodeRegistry
        NodeRegistry registryImpl = new NodeRegistry();
        bytes memory registryInitData = abi.encodeWithSelector(
            NodeRegistry.initialize.selector,
            address(tachyonToken),
            address(greenVerifier),
            address(aiOracle),
            owner
        );
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        nodeRegistry = NodeRegistry(address(registryProxy));

        // Deploy JobManager
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

        // Grant role to client and owner
        jobManager.grantRole(jobManager.JOB_CREATOR_ROLE(), client);
        jobManager.grantRole(jobManager.JOB_CREATOR_ROLE(), owner);
        
        // Grant AI_CONSUMER_ROLE to JobManager so it can call AIOracle
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), address(jobManager));

        // Fund AIOracle with LINK tokens for oracle calls
        mockLink.transfer(address(aiOracle), 10 * 10**18);

        // Mint tokens to client
        tachyonToken.mint(client, 10000 * 10**18);

        vm.stopPrank();
    }

    function testInitialization() public view {
        assertEq(address(jobManager.tachyonToken()), address(tachyonToken));
        assertEq(address(jobManager.nodeRegistry()), address(nodeRegistry));
        assertEq(address(jobManager.aiOracle()), address(aiOracle));
        assertEq(address(jobManager.greenVerifier()), address(greenVerifier));
        assertEq(jobManager.owner(), owner);
        assertTrue(jobManager.hasRole(jobManager.JOB_CREATOR_ROLE(), client));
    }

    function testCreateJob() public {
        vm.startPrank(client);
        
        // Approve payment for job
        tachyonToken.approve(address(jobManager), JOB_PAYMENT);

        // Create resource requirements
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 100,
            minBandwidthMbps: 10,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 60
        });

        JobManager.JobType jobType = JobManager.JobType.ML_INFERENCE;
        JobManager.Priority priority = JobManager.Priority.HIGH;
        uint256 deadline = block.timestamp + 1 hours;
        string memory ipfsHash = "QmXYZ123...";
        bool preferGreenNodes = true;

        vm.expectEmit(true, true, false, true);
        emit JobCreated(1, client, jobType, JOB_PAYMENT, preferGreenNodes);

        uint256 jobId = jobManager.createJob(
            jobType,
            priority,
            requirements,
            JOB_PAYMENT,
            deadline,
            ipfsHash,
            preferGreenNodes
        );

        assertEq(jobId, 1);

        vm.stopPrank();
    }

    function testCreateJobInsufficientPayment() public {
        vm.startPrank(client);
        
        // Don't approve enough tokens
        uint256 lowPayment = 5 * 10**18; // Below minimum
        tachyonToken.approve(address(jobManager), lowPayment);

        // Create resource requirements
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 2,
            minRamGB: 4,
            minStorageGB: 50,
            minBandwidthMbps: 5,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 30
        });

        vm.expectRevert("Payment below minimum");
        jobManager.createJob(
            JobManager.JobType.DATA_PROCESSING,
            JobManager.Priority.NORMAL,
            requirements,
            lowPayment,
            block.timestamp + 1 hours,
            "QmTestHash",
            false
        );

        vm.stopPrank();
    }

    function testCreateJobInvalidDeadline() public {
        vm.startPrank(client);
        
        tachyonToken.approve(address(jobManager), JOB_PAYMENT);

        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 100,
            minBandwidthMbps: 10,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 60
        });

        vm.expectRevert("Invalid deadline");
        jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.NORMAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp - 1, // Past deadline
            "QmTestHash",
            false
        );

        vm.stopPrank();
    }

    function testCreateJobEmptyIPFSHash() public {
        vm.startPrank(client);
        
        tachyonToken.approve(address(jobManager), JOB_PAYMENT);

        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 100,
            minBandwidthMbps: 10,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 60
        });

        vm.expectRevert("IPFS hash required");
        jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.NORMAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 1 hours,
            "", // Empty IPFS hash
            false
        );

        vm.stopPrank();
    }

    function testCreateJobZeroDuration() public {
        vm.startPrank(client);
        
        tachyonToken.approve(address(jobManager), JOB_PAYMENT);

        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 100,
            minBandwidthMbps: 10,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 0 // Invalid duration
        });

        vm.expectRevert("Duration required");
        jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.NORMAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 1 hours,
            "QmTestHash",
            false
        );

        vm.stopPrank();
    }

    function testGetMinJobPayment() public view {
        uint256 minPayment = jobManager.minJobPayment();
        assertEq(minPayment, 10 * 10**18); // 10 TACH minimum
    }

    function testGetMaxJobDuration() public view {
        uint256 maxDuration = jobManager.maxJobDuration();
        assertEq(maxDuration, 24 hours);
    }

    function testGetJobAssignmentTimeout() public view {
        uint256 timeout = jobManager.jobAssignmentTimeout();
        assertEq(timeout, 1 hours);
    }

    function testNextJobId() public view {
        uint256 nextId = jobManager.nextJobId();
        assertEq(nextId, 1); // Should start at 1
    }

    function testTotalJobsCreated() public view {
        uint256 totalJobs = jobManager.totalJobsCreated();
        assertEq(totalJobs, 0); // No jobs created yet
    }

    function testTotalJobsCompleted() public view {
        uint256 totalCompleted = jobManager.totalJobsCompleted();
        assertEq(totalCompleted, 0); // No jobs completed yet
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);
        
        jobManager.pause();
        assertTrue(jobManager.paused());
        
        // Should not be able to create jobs when paused
        vm.stopPrank();
        vm.startPrank(client);
        
        tachyonToken.approve(address(jobManager), JOB_PAYMENT);
        
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 2,
            minRamGB: 4,
            minStorageGB: 50,
            minBandwidthMbps: 5,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 30
        });

        vm.expectRevert(); // Generic revert due to paused state
        jobManager.createJob(
            JobManager.JobType.DATA_PROCESSING,
            JobManager.Priority.NORMAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 1 hours,
            "QmTestHash",
            false
        );
        
        vm.stopPrank();
        
        vm.startPrank(owner);
        jobManager.unpause();
        assertFalse(jobManager.paused());
        vm.stopPrank();
    }

    function testAccessControl() public {
        // Non-job-creator should not be able to create jobs
        vm.startPrank(address(0x999));
        
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 2,
            minRamGB: 4,
            minStorageGB: 50,
            minBandwidthMbps: 5,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 30
        });

        vm.expectRevert();
        jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.NORMAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 1 hours,
            "QmTestHash",
            false
        );
        
        vm.stopPrank();
    }

    function testCreateJobWithGPURequirement() public {
        vm.startPrank(client);
        
        tachyonToken.approve(address(jobManager), JOB_PAYMENT);

        // Create GPU-required job
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 8,
            minRamGB: 32,
            minStorageGB: 500,
            minBandwidthMbps: 50,
            requiresGPU: true,
            minGpuMemoryGB: 8,
            estimatedDurationMinutes: 120
        });

        uint256 jobId = jobManager.createJob(
            JobManager.JobType.RENDERING,
            JobManager.Priority.CRITICAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 2 hours,
            "QmGPUJobHash",
            true
        );

        assertEq(jobId, 1);

        vm.stopPrank();
    }

    function testCreateMultipleJobs() public {
        vm.startPrank(client);
        
        // Approve payment for multiple jobs
        tachyonToken.approve(address(jobManager), JOB_PAYMENT * 3);

        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 2,
            minRamGB: 4,
            minStorageGB: 50,
            minBandwidthMbps: 5,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 30
        });

        // Create first job
        uint256 jobId1 = jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.NORMAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 1 hours,
            "QmJob1Hash",
            false
        );

        // Create second job
        uint256 jobId2 = jobManager.createJob(
            JobManager.JobType.DATA_PROCESSING,
            JobManager.Priority.HIGH,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 2 hours,
            "QmJob2Hash",
            true
        );

        // Create third job
        uint256 jobId3 = jobManager.createJob(
            JobManager.JobType.RENDERING,
            JobManager.Priority.CRITICAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 3 hours,
            "QmJob3Hash",
            false
        );

        assertEq(jobId1, 1);
        assertEq(jobId2, 2);
        assertEq(jobId3, 3);

        vm.stopPrank();
    }

    function testJobTypeCount() public {
        vm.startPrank(client);
        
        tachyonToken.approve(address(jobManager), JOB_PAYMENT * 2);

        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 2,
            minRamGB: 4,
            minStorageGB: 50,
            minBandwidthMbps: 5,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 30
        });

        // Create ML_INFERENCE job
        jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.NORMAL,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 1 hours,
            "QmJob1Hash",
            false
        );

        // Create another ML_INFERENCE job
        jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.HIGH,
            requirements,
            JOB_PAYMENT,
            block.timestamp + 2 hours,
            "QmJob2Hash",
            true
        );

        // Check job type count
        uint256 mlInferenceCount = jobManager.jobTypeCount(JobManager.JobType.ML_INFERENCE);
        assertEq(mlInferenceCount, 2);

        uint256 dataProcessingCount = jobManager.jobTypeCount(JobManager.JobType.DATA_PROCESSING);
        assertEq(dataProcessingCount, 0);

        vm.stopPrank();
    }
}