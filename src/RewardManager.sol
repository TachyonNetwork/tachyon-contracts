// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./TachyonToken.sol";
import "./GreenVerifier.sol";
import "./AIOracle.sol";
import "./interfaces/IZKVerifier.sol";

// @title RewardManager
// @notice Manages Proof of Useful Work (PoUW) validation and reward distribution with ZK-proofs
// @dev Revolutionary feature: First DePIN to use ZK-proofs for private task validation
//      Nodes can prove work completion without revealing sensitive data (medical, financial, etc.)
//      Integrates with AI predictions and green energy multipliers for intelligent rewards
contract RewardManager is
    Initializable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant REWARD_SETTER_ROLE = keccak256("REWARD_SETTER_ROLE");

    TachyonToken public tachyonToken;
    GreenVerifier public greenVerifier;
    AIOracle public aiOracle;
    IZKVerifier public zkVerifier;

    // Task validation status
    enum ValidationStatus {
        PENDING,
        VALIDATED,
        REJECTED,
        DISPUTED
    }

    // Zero-knowledge proof data
    struct ZKProof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
        uint256[4] publicInputs; // [taskHash, resultHash, nodeAddress, timestamp]
    }

    // Task result with ZK validation
    struct TaskResult {
        bytes32 taskId;
        address node;
        bytes32 resultHash;
        uint256 timestamp;
        ValidationStatus status;
        uint256 baseReward;
        uint256 finalReward; // After multipliers
        bool zkValidated;
        ZKProof proof;
    }

    // Reward configuration
    struct RewardConfig {
        uint256 baseRewardPerTask;
        uint256 minStakeRequired;
        uint256 validationTimeout;
        uint256 disputePeriod;
        bool zkRequired;
    }

    // Storage
    mapping(bytes32 => TaskResult) public taskResults;
    mapping(address => uint256) public nodeRewards;
    mapping(address => uint256) public pendingRewards;
    mapping(bytes32 => bool) public processedTasks;

    RewardConfig public rewardConfig;
    uint256 public totalRewardsDistributed;
    uint256 public totalTasksValidated;

    // AI-driven dynamic rewards
    mapping(bytes32 => uint256) public taskTypeDemandMultiplier; // Based on AI predictions

    // Events
    event TaskSubmitted(bytes32 indexed taskId, address indexed node, bytes32 resultHash);
    event TaskValidated(bytes32 indexed taskId, uint256 reward, bool zkProof);
    event RewardDistributed(address indexed node, uint256 amount, uint256 greenMultiplier);
    event ZKProofVerified(bytes32 indexed taskId, address indexed node);
    event RewardConfigUpdated(uint256 baseReward, bool zkRequired);
    event DisputeRaised(bytes32 indexed taskId, address indexed disputer);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tachyonToken,
        address _greenVerifier,
        address _aiOracle,
        address _zkVerifier,
        address initialOwner
    ) public initializer {
        __AccessControl_init();
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        tachyonToken = TachyonToken(payable(_tachyonToken));
        greenVerifier = GreenVerifier(_greenVerifier);
        aiOracle = AIOracle(_aiOracle);
        zkVerifier = IZKVerifier(_zkVerifier);

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(VALIDATOR_ROLE, initialOwner);
        _grantRole(REWARD_SETTER_ROLE, initialOwner);

        // Initialize default reward config
        rewardConfig = RewardConfig({
            baseRewardPerTask: 100 * 10 ** 18, // 100 TACH base reward
            minStakeRequired: 1000 * 10 ** 18, // 1000 TACH minimum stake
            validationTimeout: 1 hours,
            disputePeriod: 24 hours,
            zkRequired: true
        });
    }

    // @notice Submit task completion with optional ZK proof
    // @param taskId Unique task identifier
    // @param resultHash Hash of the computation result
    // @param proof Zero-knowledge proof of valid computation
    function submitTaskCompletion(bytes32 taskId, bytes32 resultHash, ZKProof calldata proof)
        external
        whenNotPaused
        nonReentrant
    {
        require(!processedTasks[taskId], "Task already processed");
        require(resultHash != bytes32(0), "Invalid result hash");

        // Store task result
        taskResults[taskId] = TaskResult({
            taskId: taskId,
            node: msg.sender,
            resultHash: resultHash,
            timestamp: block.timestamp,
            status: ValidationStatus.PENDING,
            baseReward: rewardConfig.baseRewardPerTask,
            finalReward: 0,
            zkValidated: false,
            proof: proof
        });

        emit TaskSubmitted(taskId, msg.sender, resultHash);

        // Auto-validate if ZK proof provided
        if (rewardConfig.zkRequired) {
            _validateWithZKProof(taskId);
        }
    }

    // @notice Validate task with ZK proof
    function _validateWithZKProof(bytes32 taskId) internal {
        TaskResult storage result = taskResults[taskId];

        // Prepare public inputs for ZK verification
        uint256[4] memory publicInputs =
            [uint256(taskId), uint256(result.resultHash), uint256(uint160(result.node)), result.timestamp];

        // Verify ZK proof
        bool valid = zkVerifier.verifyProof(result.proof.a, result.proof.b, result.proof.c, publicInputs);

        if (valid) {
            result.zkValidated = true;
            result.status = ValidationStatus.VALIDATED;
            emit ZKProofVerified(taskId, result.node);

            _calculateAndDistributeReward(taskId);
        } else {
            result.status = ValidationStatus.REJECTED;
        }
    }

    // @notice Manual validation by authorized validator (fallback)
    function validateTask(bytes32 taskId, bool approved) external onlyRole(VALIDATOR_ROLE) {
        TaskResult storage result = taskResults[taskId];
        require(result.status == ValidationStatus.PENDING, "Invalid status");
        require(!rewardConfig.zkRequired || !result.zkValidated, "Already ZK validated");

        if (approved) {
            result.status = ValidationStatus.VALIDATED;
            _calculateAndDistributeReward(taskId);
        } else {
            result.status = ValidationStatus.REJECTED;
        }

        emit TaskValidated(taskId, result.finalReward, result.zkValidated);
    }

    // @notice Calculate reward with multipliers
    function _calculateAndDistributeReward(bytes32 taskId) internal {
        TaskResult storage result = taskResults[taskId];

        uint256 reward = result.baseReward;

        uint256 greenMultiplier = greenVerifier.getRewardMultiplier(result.node);
        reward = (reward * greenMultiplier) / 100;

        bytes32 taskType = _getTaskType(taskId);
        uint256 demandMultiplier = taskTypeDemandMultiplier[taskType];
        if (demandMultiplier > 0) {
            reward = (reward * demandMultiplier) / 100;
        }

        uint256 nodeScore = aiOracle.nodeScores(result.node);
        if (nodeScore > 80) {
            reward = (reward * 110) / 100;
        }

        result.finalReward = reward;
        pendingRewards[result.node] += reward;
        totalRewardsDistributed += reward;
        totalTasksValidated++;

        processedTasks[taskId] = true;

        emit RewardDistributed(result.node, reward, greenMultiplier);
    }

    // @notice Claim accumulated rewards
    function claimRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No rewards to claim");

        pendingRewards[msg.sender] = 0;
        nodeRewards[msg.sender] += amount;

        tachyonToken.mint(msg.sender, amount);
    }

    // @notice Update reward configuration
    function updateRewardConfig(uint256 _baseReward, uint256 _minStake, bool _zkRequired)
        external
        onlyRole(REWARD_SETTER_ROLE)
    {
        rewardConfig.baseRewardPerTask = _baseReward;
        rewardConfig.minStakeRequired = _minStake;
        rewardConfig.zkRequired = _zkRequired;

        emit RewardConfigUpdated(_baseReward, _zkRequired);
    }

    // @notice Update task demand multiplier based on AI predictions
    function updateDemandMultiplier(bytes32 taskType, uint256 multiplier) external onlyRole(VALIDATOR_ROLE) {
        require(multiplier >= 50 && multiplier <= 300, "Invalid multiplier range");
        taskTypeDemandMultiplier[taskType] = multiplier;
    }

    // @notice Raise dispute for validated task
    function disputeTask(bytes32 taskId) external {
        TaskResult storage result = taskResults[taskId];
        require(result.status == ValidationStatus.VALIDATED, "Not validated");
        require(block.timestamp <= result.timestamp + rewardConfig.disputePeriod, "Dispute period ended");

        result.status = ValidationStatus.DISPUTED;
        emit DisputeRaised(taskId, msg.sender);
    }

    // @notice Update ZK verifier contract
    function updateZKVerifier(address _zkVerifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        zkVerifier = IZKVerifier(_zkVerifier);
    }

    // @notice Get task validation details
    function getTaskDetails(bytes32 taskId)
        external
        view
        returns (address node, uint256 reward, ValidationStatus status, bool zkValidated)
    {
        TaskResult memory result = taskResults[taskId];
        return (result.node, result.finalReward, result.status, result.zkValidated);
    }

    // @notice Get node statistics
    function getNodeStats(address node)
        external
        view
        returns (uint256 totalRewards, uint256 pendingAmount, uint256 greenMultiplier, uint256 aiScore)
    {
        totalRewards = nodeRewards[node];
        pendingAmount = pendingRewards[node];
        greenMultiplier = greenVerifier.getRewardMultiplier(node);
        aiScore = aiOracle.nodeScores(node);
    }

    // Internal helper to determine task type
    function _getTaskType(bytes32 taskId) internal pure returns (bytes32) {
        bytes32 typeHash = keccak256(abi.encodePacked(taskId, "type"));

        if (uint256(typeHash) % 4 == 0) return keccak256("ML_INFERENCE");
        if (uint256(typeHash) % 4 == 1) return keccak256("DATA_PROCESSING");
        if (uint256(typeHash) % 4 == 2) return keccak256("RENDERING");
        return keccak256("COMPUTE");
    }

    // Emergency functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}
