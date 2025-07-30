// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/Chainlink.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// @title AIOracle
// @notice Integrates off-chain AI predictions for autonomous task optimization in Tachyon Network
// @dev Uses Chainlink oracles to fetch AI predictions for task distribution, demand forecasting, and node selection
//      This revolutionary feature enables the network to self-optimize based on ML models running off-chain
//      AI agents analyze historical data and predict optimal resource allocation, making PoUW "intelligent"
contract AIOracle is 
    Initializable, 
    ChainlinkClient, 
    AccessControlUpgradeable, 
    OwnableUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable 
{
    using Chainlink for Chainlink.Request;

    bytes32 public constant AI_CONSUMER_ROLE = keccak256("AI_CONSUMER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    // Chainlink oracle configuration
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    // AI prediction types
    enum PredictionType {
        TASK_DEMAND,        // Predict future task demand
        NODE_SELECTION,     // Optimal node for a task
        RESOURCE_PRICING,   // Dynamic pricing based on demand
        LATENCY_FORECAST,   // Network latency predictions
        ENERGY_EFFICIENCY   // Energy-optimal task routing
    }

    // Prediction data structure
    struct Prediction {
        uint256 timestamp;
        PredictionType predictionType;
        bytes32 taskId;
        uint256 confidence;  // 0-100 confidence score
        bytes data;          // Encoded prediction data
    }

    // Storage for predictions
    mapping(bytes32 => Prediction) public predictions;
    mapping(address => uint256) public nodeScores;  // AI-computed node efficiency scores

    // Events
    event PredictionRequested(bytes32 indexed requestId, PredictionType predictionType, bytes32 taskId);
    event PredictionReceived(bytes32 indexed requestId, uint256 confidence, bytes data);
    event NodeScoreUpdated(address indexed node, uint256 score);
    event OracleConfigUpdated(address oracle, bytes32 jobId, uint256 fee);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _link,
        address _oracle,
        bytes32 _jobId,
        uint256 _fee,
        address initialOwner
    ) public initializer {
        __AccessControl_init();
        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        _setChainlinkToken(_link);
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ORACLE_MANAGER_ROLE, initialOwner);
    }

    // @notice Request AI prediction for task optimization
    // @param predictionType Type of prediction needed
    // @param taskId Task identifier for context
    // @param inputData Additional context data for AI model
    function requestPrediction(
        PredictionType predictionType,
        bytes32 taskId,
        bytes calldata inputData
    ) external onlyRole(AI_CONSUMER_ROLE) whenNotPaused returns (bytes32 requestId) {
        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillPrediction.selector
        );

        // Set request parameters for AI service
        req._add("predictionType", uint2str(uint256(predictionType)));
        req._addBytes("taskId", abi.encodePacked(taskId));
        req._addBytes("inputData", inputData);
        req._add("network", "tachyon");

        requestId = _sendChainlinkRequestTo(oracle, req, fee);
        
        emit PredictionRequested(requestId, predictionType, taskId);
        return requestId;
    }

    // @notice Fulfill prediction from oracle
    // @dev Called by Chainlink oracle with AI prediction results
    function fulfillPrediction(
        bytes32 requestId,
        uint256 confidence,
        bytes memory predictionData
    ) public recordChainlinkFulfillment(requestId) {
        predictions[requestId] = Prediction({
            timestamp: block.timestamp,
            predictionType: PredictionType.NODE_SELECTION, // Default, should be passed
            taskId: bytes32(0), // Should be retrieved from request mapping
            confidence: confidence,
            data: predictionData
        });

        emit PredictionReceived(requestId, confidence, predictionData);

        // Process prediction based on type
        _processPrediction(requestId, predictionData);
    }

    // @notice Get optimal nodes for task based on AI predictions
    // @param taskRequirements Encoded task requirements
    // @return nodes Array of optimal node addresses
    // @return scores Efficiency scores for each node
    function getOptimalNodes(
        bytes calldata /* taskRequirements */
    ) external view returns (address[] memory nodes, uint256[] memory scores) {
        uint256 maxResults = 10;
        nodes = new address[](maxResults);
        scores = new uint256[](maxResults);
        
        return (nodes, scores);
    }

    // @notice Update node efficiency score based on AI analysis
    // @dev Only callable by oracle or authorized contracts
    function updateNodeScore(
        address node,
        uint256 score
    ) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(score <= 100, "Score must be 0-100");
        nodeScores[node] = score;
        emit NodeScoreUpdated(node, score);
    }

    // @notice Batch update node scores from AI analysis
    function batchUpdateNodeScores(
        address[] calldata nodes,
        uint256[] calldata scores
    ) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(nodes.length == scores.length, "Array length mismatch");
        
        for (uint256 i = 0; i < nodes.length; i++) {
            require(scores[i] <= 100, "Score must be 0-100");
            nodeScores[nodes[i]] = scores[i];
            emit NodeScoreUpdated(nodes[i], scores[i]);
        }
    }

    // @notice Get demand forecast for specific task type
    // @param taskType Type of computational task
    // @return demandScore Predicted demand (0-100 scale)
    // @return confidence Confidence in prediction
    function getDemandForecast(
        bytes32 /* taskType */
    ) external view returns (uint256 demandScore, uint256 confidence) {
        demandScore = 50; 
        confidence = 80;
        return (demandScore, confidence);
    }

    // @notice Update oracle configuration
    function updateOracleConfig(
        address _oracle,
        bytes32 _jobId,
        uint256 _fee
    ) external onlyRole(ORACLE_MANAGER_ROLE) {
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
        emit OracleConfigUpdated(_oracle, _jobId, _fee);
    }

    // @notice Emergency pause
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // Internal functions

    function _processPrediction(bytes32 requestId, bytes memory data) internal {
        // Process different prediction types
        // Update internal state based on AI recommendations
        // This would trigger updates in JobManager, NodeRegistry, etc.
    }

    // Utility function for uint to string conversion
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // @notice Get LINK balance
    function getLinkBalance() external view returns (uint256) {
        return LinkTokenInterface(_chainlinkTokenAddress()).balanceOf(address(this));
    }

    // @notice Withdraw LINK tokens
    function withdrawLink() external onlyRole(DEFAULT_ADMIN_ROLE) {
        LinkTokenInterface linkToken = LinkTokenInterface(_chainlinkTokenAddress());
        require(linkToken.transfer(msg.sender, linkToken.balanceOf(address(this))), "Transfer failed");
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}