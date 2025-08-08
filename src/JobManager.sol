// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./TachyonToken.sol";
import "./NodeRegistry.sol";
import "./AIOracle.sol";
import "./GreenVerifier.sol";

// @title JobManager
// @notice Advanced job management with AI-powered task distribution and green energy prioritization
// @dev Consensys best practices: upgradeable, modular, access controlled, comprehensive events
//      Revolutionary features: AI-optimized job routing, green node prioritization, dynamic pricing
//      UUPS upgradeable for future enhancements (quantum-resistant algorithms, new AI models)
contract JobManager is
    Initializable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant JOB_CREATOR_ROLE = keccak256("JOB_CREATOR_ROLE");
    bytes32 public constant JOB_VALIDATOR_ROLE = keccak256("JOB_VALIDATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Core contract dependencies
    TachyonToken public tachyonToken;
    NodeRegistry public nodeRegistry;
    AIOracle public aiOracle;
    GreenVerifier public greenVerifier;

    // Job types for AI optimization
    enum JobType {
        ML_INFERENCE,
        DATA_PROCESSING,
        RENDERING,
        SCIENTIFIC_COMPUTE,
        IOT_AGGREGATION,
        CLIMATE_MODELING,
        MEDICAL_ANALYSIS
    }

    // Job priority levels
    enum Priority {
        LOW,
        NORMAL,
        HIGH,
        CRITICAL
    }

    // Job status lifecycle
    enum JobStatus {
        CREATED,
        ASSIGNED,
        IN_PROGRESS,
        COMPLETED,
        DISPUTED,
        CANCELLED
    }

    // Resource requirements structure
    struct ResourceRequirements {
        uint256 minCpuCores;
        uint256 minRamGB;
        uint256 minStorageGB;
        uint256 minBandwidthMbps;
        bool requiresGPU;
        uint256 minGpuMemoryGB;
        uint256 estimatedDurationMinutes;
    }

    // Job specification
    struct Job {
        uint256 jobId;
        address client;
        JobType jobType;
        Priority priority;
        JobStatus status;
        ResourceRequirements requirements;
        uint256 payment;
        uint256 createdAt;
        uint256 deadline;
        bytes32 dataHash;
        string ipfsHash;
        address assignedNode;
        uint256 assignedAt;
        bool preferGreenNodes;
        uint256 completedAt;
        bytes32 resultHash;
    }

    // AI-driven pricing structure
    struct DynamicPricing {
        uint256 basePrice;
        uint256 demandMultiplier;
        uint256 urgencyMultiplier;
        uint256 greenBonus;
        uint256 finalPrice;
    }

    // Storage
    mapping(uint256 => Job) public jobs;
    mapping(address => uint256[]) public clientJobs;
    mapping(address => uint256[]) public nodeJobs;
    mapping(JobType => uint256) public jobTypeCount;
    mapping(bytes32 => uint256) public ipfsHashToJobId;

    // Configuration
    uint256 public nextJobId;
    uint256 public minJobPayment;
    uint256 public maxJobDuration;
    uint256 public jobAssignmentTimeout;
    uint256 public totalJobsCreated;
    uint256 public totalJobsCompleted;

    // AI-optimized job queues
    uint256[] public priorityQueue;
    uint256[] public greenPreferredQueue;
    mapping(JobType => uint256[]) public jobTypeQueues;
    mapping(uint256 => bool) public jobSettled;

    // Events (Consensys: comprehensive event logging)
    event JobCreated(uint256 indexed jobId, address indexed client, JobType jobType, uint256 payment, bool preferGreen);
    event JobAssigned(uint256 indexed jobId, address indexed node, uint256 aiScore, uint256 greenMultiplier);
    event JobCompleted(uint256 indexed jobId, address indexed node, bytes32 resultHash, uint256 duration);
    event JobCancelled(uint256 indexed jobId, address indexed client, string reason);
    event DynamicPricingCalculated(uint256 indexed jobId, DynamicPricing pricing);
    event AIOptimizationApplied(uint256 indexed jobId, address[] recommendedNodes);
    event GreenNodePrioritized(uint256 indexed jobId, address indexed node);
    event JobSettled(uint256 indexed jobId, address indexed node, uint256 amount);

    // @dev Constructor disabled for upgradeable contracts
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // @notice Initialize the contract with dependencies and configuration
    // @dev Consensys pattern: single initialization with all dependencies
    function initialize(
        address _tachyonToken,
        address _nodeRegistry,
        address _aiOracle,
        address _greenVerifier,
        address initialOwner
    ) public initializer {
        __AccessControl_init();
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Set contract dependencies
        tachyonToken = TachyonToken(payable(_tachyonToken));
        nodeRegistry = NodeRegistry(_nodeRegistry);
        aiOracle = AIOracle(_aiOracle);
        greenVerifier = GreenVerifier(_greenVerifier);

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(JOB_CREATOR_ROLE, initialOwner);
        _grantRole(JOB_VALIDATOR_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, initialOwner);

        // Initialize configuration
        nextJobId = 1;
        minJobPayment = 10 * 10 ** 18; // 10 TACH minimum
        maxJobDuration = 24 hours;
        jobAssignmentTimeout = 1 hours;
    }

    // @notice Create a new computational job with AI optimization
    // @dev Consensys: comprehensive input validation, reentrancy protection
    function createJob(
        JobType jobType,
        Priority priority,
        ResourceRequirements calldata requirements,
        uint256 payment,
        uint256 deadline,
        string calldata ipfsHash,
        bool preferGreenNodes
    ) external whenNotPaused nonReentrant returns (uint256 jobId) {
        require(payment >= minJobPayment, "Payment below minimum");
        require(deadline > block.timestamp, "Invalid deadline");
        require(deadline <= block.timestamp + maxJobDuration, "Deadline too far");
        require(bytes(ipfsHash).length > 0, "IPFS hash required");
        require(requirements.estimatedDurationMinutes > 0, "Duration required");

        // Transfer payment to contract
        require(tachyonToken.transferFrom(msg.sender, address(this), payment), "Payment transfer failed");

        jobId = nextJobId++;
        bytes32 dataHash = keccak256(abi.encodePacked(jobId, msg.sender, ipfsHash));

        // Create job record
        jobs[jobId] = Job({
            jobId: jobId,
            client: msg.sender,
            jobType: jobType,
            priority: priority,
            status: JobStatus.CREATED,
            requirements: requirements,
            payment: payment,
            createdAt: block.timestamp,
            deadline: deadline,
            dataHash: dataHash,
            ipfsHash: ipfsHash,
            assignedNode: address(0),
            assignedAt: 0,
            preferGreenNodes: preferGreenNodes,
            completedAt: 0,
            resultHash: bytes32(0)
        });

        // Update indices
        clientJobs[msg.sender].push(jobId);
        jobTypeCount[jobType]++;
        totalJobsCreated++;
        ipfsHashToJobId[keccak256(bytes(ipfsHash))] = jobId;

        // Add to appropriate queues
        _addToQueues(jobId, priority, jobType, preferGreenNodes);

        emit JobCreated(jobId, msg.sender, jobType, payment, preferGreenNodes);

        // Trigger AI optimization for job assignment
        _requestAIOptimization(jobId);

        return jobId;
    }

    // @notice AI-powered job assignment to optimal nodes
    // @dev Revolutionary: Uses AI predictions and green preferences
    function assignJobToOptimalNode(uint256 jobId) external onlyRole(JOB_VALIDATOR_ROLE) {
        Job storage job = jobs[jobId];
        require(job.status == JobStatus.CREATED, "Job not available for assignment");
        require(block.timestamp <= job.deadline, "Job deadline passed");

        // Get AI-recommended nodes
        address[] memory suitableNodes = nodeRegistry.getNodesForTask(
            job.requirements.minCpuCores, job.requirements.minRamGB, job.requirements.requiresGPU, job.preferGreenNodes
        );

        require(suitableNodes.length > 0, "No suitable nodes available");

        // Calculate dynamic pricing with AI predictions
        DynamicPricing memory pricing = _calculateDynamicPricing(jobId, job);

        // Select optimal node using AI and green preferences
        address selectedNode = _selectOptimalNode(jobId, suitableNodes, job.preferGreenNodes);

        // Assign job
        job.assignedNode = selectedNode;
        job.assignedAt = block.timestamp;
        job.status = JobStatus.ASSIGNED;

        nodeJobs[selectedNode].push(jobId);

        // Track active tasks on the node
        try nodeRegistry.incrementActiveTasks(selectedNode) {} catch {}

        // Get metrics for event
        uint256 aiScore = aiOracle.nodeScores(selectedNode);
        uint256 greenMultiplier = greenVerifier.getRewardMultiplier(selectedNode);

        emit JobAssigned(jobId, selectedNode, aiScore, greenMultiplier);
        emit DynamicPricingCalculated(jobId, pricing);

        if (job.preferGreenNodes && greenVerifier.isNodeGreen(selectedNode)) {
            emit GreenNodePrioritized(jobId, selectedNode);
        }
    }

    // @notice Complete a job with result submission
    function completeJob(uint256 jobId, bytes32 resultHash, string calldata resultIpfsHash)
        external
        whenNotPaused
        nonReentrant
    {
        Job storage job = jobs[jobId];
        require(job.assignedNode == msg.sender, "Not assigned to caller");
        require(job.status == JobStatus.ASSIGNED || job.status == JobStatus.IN_PROGRESS, "Invalid status");
        require(resultHash != bytes32(0), "Invalid result hash");
        require(bytes(resultIpfsHash).length > 0, "Result IPFS hash required");

        job.status = JobStatus.COMPLETED;
        job.completedAt = block.timestamp;
        job.resultHash = resultHash;

        totalJobsCompleted++;

        uint256 duration = block.timestamp - job.assignedAt;
        emit JobCompleted(jobId, msg.sender, resultHash, duration);

        // Update node reputation based on completion
        nodeRegistry.updateReputation(msg.sender, true);

        // Decrement active tasks counter safely
        try nodeRegistry.decrementActiveTasks(msg.sender) {} catch {}
    }

    // @notice Settle job escrow to assigned node after successful completion
    // @dev Callable by client or validators; prevents double payout
    function settleJob(uint256 jobId) external whenNotPaused nonReentrant {
        Job storage job = jobs[jobId];
        require(job.status == JobStatus.COMPLETED, "Job not completed");
        require(!jobSettled[jobId], "Already settled");
        require(
            msg.sender == job.client || hasRole(JOB_VALIDATOR_ROLE, msg.sender),
            "Unauthorized to settle"
        );

        jobSettled[jobId] = true;
        require(tachyonToken.transfer(job.assignedNode, job.payment), "Payout failed");
        emit JobSettled(jobId, job.assignedNode, job.payment);
    }

    // @notice Cancel a job (by client or admin)
    function cancelJob(uint256 jobId, string calldata reason) external {
        Job storage job = jobs[jobId];
        require(msg.sender == job.client || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized to cancel");
        require(job.status == JobStatus.CREATED || job.status == JobStatus.ASSIGNED, "Cannot cancel");

        job.status = JobStatus.CANCELLED;

        // Refund payment to client
        require(tachyonToken.transfer(job.client, job.payment), "Refund failed");

        emit JobCancelled(jobId, job.client, reason);

        // If was assigned, decrement active tasks for that node
        if (job.assignedNode != address(0)) {
            try nodeRegistry.decrementActiveTasks(job.assignedNode) {} catch {}
        }
    }

    // @notice Get AI-optimized job recommendations for a node
    function getRecommendedJobs(address node) external view returns (uint256[] memory recommendedJobs) {
        // Get node capabilities and scores
        (NodeRegistry.NodeInfo memory nodeInfo, uint256 greenMultiplier, uint256 aiScore) =
            nodeRegistry.getNodeDetails(node);

        // Filter jobs based on node capabilities, green preference, and AI score
        uint256 count = 0;
        uint256[] memory temp = new uint256[](priorityQueue.length);

        for (uint256 i = 0; i < priorityQueue.length; i++) {
            uint256 jobId = priorityQueue[i];
            Job memory job = jobs[jobId];

            if (job.status == JobStatus.CREATED && _isNodeSuitable(job, nodeInfo)) {
                // Prioritize green jobs for green nodes and high AI score nodes
                bool isPreferred = (job.preferGreenNodes && greenMultiplier > 100) || aiScore > 75;
                if (isPreferred || count < 5) {
                    // Always include first 5 suitable jobs
                    temp[count] = jobId;
                    count++;
                }
            }
        }

        recommendedJobs = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            recommendedJobs[i] = temp[i];
        }

        return recommendedJobs;
    }

    // @notice Get comprehensive job statistics
    function getJobStatistics()
        external
        view
        returns (uint256 total, uint256 completed, uint256 active, uint256 completionRate, uint256 avgGreenJobs)
    {
        total = totalJobsCreated;
        completed = totalJobsCompleted;
        active = total - completed;
        completionRate = total > 0 ? (completed * 100) / total : 0;

        // Calculate green job percentage
        uint256 greenJobCount = 0;
        for (uint256 i = 1; i < nextJobId; i++) {
            if (jobs[i].preferGreenNodes) {
                greenJobCount++;
            }
        }
        avgGreenJobs = total > 0 ? (greenJobCount * 100) / total : 0;
    }

    // Internal functions

    function _addToQueues(uint256 jobId, Priority priority, JobType jobType, bool preferGreen) internal {
        if (priority == Priority.HIGH || priority == Priority.CRITICAL) {
            priorityQueue.push(jobId);
        }

        if (preferGreen) {
            greenPreferredQueue.push(jobId);
        }

        jobTypeQueues[jobType].push(jobId);
    }

    function _requestAIOptimization(uint256 jobId) internal {
        Job memory job = jobs[jobId];

        // Prepare input data for AI oracle
        bytes memory inputData =
            abi.encode(job.jobType, job.requirements, job.priority, job.preferGreenNodes, job.deadline);

        // Request AI prediction for optimal node selection
        // External call guarded with try/catch to avoid reverts bubbling
        try aiOracle.requestPrediction(AIOracle.PredictionType.NODE_SELECTION, bytes32(jobId), inputData) returns (
            bytes32 /* requestId */
        ) {
            // no-op
        } catch {
            // ignore oracle errors in job creation flow
        }
    }

    function _calculateDynamicPricing(uint256, /* jobId */ Job memory job)
        internal
        view
        returns (DynamicPricing memory)
    {
        uint256 basePrice = job.payment;

        // Get demand prediction from AI oracle
        (uint256 demandScore, uint256 urgency, uint256 confidence) =
            aiOracle.getDemandForecast(keccak256(abi.encodePacked(job.jobType)));

        // Adjust demand multiplier based on confidence
        uint256 confidenceAdjustment = confidence < 50 ? 100 : 100 + (confidence - 50) / 10;
        uint256 demandMultiplier = (100 + (demandScore * 50) / 100) * confidenceAdjustment / 100;

        // Combine job priority with AI urgency prediction
        uint256 basePriorityMultiplier =
            job.priority == Priority.CRITICAL ? 150 : job.priority == Priority.HIGH ? 125 : 100;
        uint256 aiUrgencyMultiplier = 100 + (urgency * 25) / 100; // 0-25% boost based on AI urgency
        uint256 urgencyMultiplier = (basePriorityMultiplier * aiUrgencyMultiplier) / 100;

        uint256 greenBonus = job.preferGreenNodes ? 110 : 100; // 10% bonus for green preference

        uint256 finalPrice = (basePrice * demandMultiplier * urgencyMultiplier * greenBonus) / (100 * 100 * 100);

        return DynamicPricing({
            basePrice: basePrice,
            demandMultiplier: demandMultiplier,
            urgencyMultiplier: urgencyMultiplier,
            greenBonus: greenBonus,
            finalPrice: finalPrice
        });
    }

    function _selectOptimalNode(uint256 jobId, address[] memory suitableNodes, bool preferGreen)
        internal
        returns (address)
    {
        uint256 bestScore = 0;
        address bestNode = suitableNodes[0];

        for (uint256 i = 0; i < suitableNodes.length; i++) {
            address node = suitableNodes[i];
            uint256 score = _calculateNodeScore(node, preferGreen);

            if (score > bestScore) {
                bestScore = score;
                bestNode = node;
            }
        }

        // Emit AI optimization event
        emit AIOptimizationApplied(jobId, suitableNodes);

        return bestNode;
    }

    function _calculateNodeScore(address node, bool preferGreen) internal view returns (uint256) {
        uint256 aiScore = aiOracle.nodeScores(node);
        uint256 greenMultiplier = greenVerifier.getRewardMultiplier(node);

        (NodeRegistry.NodeInfo memory nodeInfo,,) = nodeRegistry.getNodeDetails(node);
        uint256 reputationScore = nodeInfo.reputation;

        uint256 totalScore = (aiScore * 40 + reputationScore * 30 + greenMultiplier * 30) / 100;

        // Bonus for green nodes if preferred
        if (preferGreen && greenVerifier.isNodeGreen(node)) {
            totalScore = (totalScore * 120) / 100; // 20% bonus
        }

        return totalScore;
    }

    function _isNodeSuitable(Job memory job, NodeRegistry.NodeInfo memory node) internal pure returns (bool) {
        return node.capabilities.cpuCores >= job.requirements.minCpuCores
            && node.capabilities.ramGB >= job.requirements.minRamGB
            && node.capabilities.storageGB >= job.requirements.minStorageGB
            && (!job.requirements.requiresGPU || node.capabilities.hasGPU)
            && (job.requirements.requiresGPU ? node.capabilities.gpuMemoryGB >= job.requirements.minGpuMemoryGB : true);
    }

    // Admin functions

    function updateConfiguration(uint256 _minJobPayment, uint256 _maxJobDuration, uint256 _jobAssignmentTimeout)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        minJobPayment = _minJobPayment;
        maxJobDuration = _maxJobDuration;
        jobAssignmentTimeout = _jobAssignmentTimeout;
    }

    function updateContractAddresses(
        address _tachyonToken,
        address _nodeRegistry,
        address _aiOracle,
        address _greenVerifier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_tachyonToken != address(0)) tachyonToken = TachyonToken(payable(_tachyonToken));
        if (_nodeRegistry != address(0)) nodeRegistry = NodeRegistry(_nodeRegistry);
        if (_aiOracle != address(0)) aiOracle = AIOracle(_aiOracle);
        if (_greenVerifier != address(0)) greenVerifier = GreenVerifier(_greenVerifier);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}
