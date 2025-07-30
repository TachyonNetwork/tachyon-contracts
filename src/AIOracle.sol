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
        TASK_DEMAND, // Predict future task demand
        NODE_SELECTION, // Optimal node for a task
        RESOURCE_PRICING, // Dynamic pricing based on demand
        LATENCY_FORECAST, // Network latency predictions
        ENERGY_EFFICIENCY // Energy-optimal task routing

    }

    // Prediction data structure
    struct Prediction {
        uint256 timestamp;
        PredictionType predictionType;
        bytes32 taskId;
        uint256 confidence; // 0-100 confidence score
        bytes data; // Encoded prediction data
    }

    // Storage for predictions
    mapping(bytes32 => Prediction) public predictions;
    mapping(address => uint256) public nodeScores; // AI-computed node efficiency scores
    
    // Additional prediction storage
    struct TaskDemand {
        uint256 demandScore;
        uint256 urgency;
        uint256 timestamp;
    }
    
    struct PricingPrediction {
        uint256 basePriceMultiplier;
        uint256 demandMultiplier;
        uint256 lastUpdate;
    }
    
    mapping(bytes32 => TaskDemand) public taskDemandPredictions;
    mapping(address => uint256) public nodeLatencies; // Predicted latencies in milliseconds
    mapping(address => uint256) public nodeEnergyEfficiency; // Energy efficiency scores
    PricingPrediction public pricingPredictions;

    // Events
    event PredictionRequested(bytes32 indexed requestId, PredictionType predictionType, bytes32 taskId);
    event PredictionReceived(bytes32 indexed requestId, uint256 confidence, bytes data);
    event NodeScoreUpdated(address indexed node, uint256 score);
    event OracleConfigUpdated(address oracle, bytes32 jobId, uint256 fee);
    event PredictionProcessed(bytes32 indexed requestId, PredictionType predictionType);
    event TaskDemandUpdated(bytes32 indexed taskId, uint256 demandScore, uint256 urgency);
    event PricingUpdated(uint256 basePriceMultiplier, uint256 demandMultiplier);
    event NodeLatencyUpdated(address indexed node, uint256 latency);
    event NodeEnergyEfficiencyUpdated(address indexed node, uint256 efficiency);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _link, address _oracle, bytes32 _jobId, uint256 _fee, address initialOwner)
        public
        initializer
    {
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
    function requestPrediction(PredictionType predictionType, bytes32 taskId, bytes calldata inputData)
        external
        onlyRole(AI_CONSUMER_ROLE)
        whenNotPaused
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = _buildChainlinkRequest(jobId, address(this), this.fulfillPrediction.selector);

        // Set request parameters for AI service
        req._add("predictionType", uint2str(uint256(predictionType)));
        req._addBytes("taskId", abi.encodePacked(taskId));
        req._addBytes("inputData", inputData);
        req._add("network", "tachyon");

        requestId = _sendChainlinkRequestTo(oracle, req, fee);
        
        // Store request context
        pendingRequests[requestId] = PredictionRequest({
            predictionType: predictionType,
            taskId: taskId,
            requester: msg.sender,
            timestamp: block.timestamp
        });

        emit PredictionRequested(requestId, predictionType, taskId);
        return requestId;
    }

    // Storage for request context
    mapping(bytes32 => PredictionRequest) public pendingRequests;
    
    struct PredictionRequest {
        PredictionType predictionType;
        bytes32 taskId;
        address requester;
        uint256 timestamp;
    }
    
    // Minimum confidence threshold
    uint256 public constant MIN_CONFIDENCE = 70; // 70%
    
    // Oracle manipulation protection
    mapping(address => uint256) public lastOracleUpdate;
    uint256 public constant ORACLE_COOLDOWN = 5 minutes;

    // @notice Fulfill prediction from oracle
    // @dev Called by Chainlink oracle with AI prediction results
    function fulfillPrediction(bytes32 requestId, uint256 confidence, bytes memory predictionData)
        public
        recordChainlinkFulfillment(requestId)
    {
        require(confidence >= MIN_CONFIDENCE, "Confidence too low");
        require(block.timestamp >= lastOracleUpdate[msg.sender] + ORACLE_COOLDOWN, "Oracle cooldown active");
        
        PredictionRequest memory request = pendingRequests[requestId];
        require(request.timestamp > 0, "Invalid request");
        
        predictions[requestId] = Prediction({
            timestamp: block.timestamp,
            predictionType: request.predictionType,
            taskId: request.taskId,
            confidence: confidence,
            data: predictionData
        });

        lastOracleUpdate[msg.sender] = block.timestamp;
        
        emit PredictionReceived(requestId, confidence, predictionData);

        // Process prediction based on type
        _processPrediction(requestId, request, predictionData);
        
        // Clean up
        delete pendingRequests[requestId];
    }

    // @notice Get optimal nodes for task based on AI predictions
    // @param taskRequirements Encoded task requirements
    // @return nodes Array of optimal node addresses
    // @return scores Efficiency scores for each node
    function getOptimalNodes(bytes calldata /* taskRequirements */)
        external
        pure
        returns (address[] memory nodes, uint256[] memory scores)
    {
        // For now, return empty arrays - would be populated by AI predictions
        uint256 maxResults = 10;
        nodes = new address[](maxResults);
        scores = new uint256[](maxResults);
        
        return (nodes, scores);
    }

    // @notice Update node efficiency score based on AI analysis
    // @dev Only callable by oracle or authorized contracts
    function updateNodeScore(address node, uint256 score) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(score <= 100, "Score must be 0-100");
        nodeScores[node] = score;
        emit NodeScoreUpdated(node, score);
    }

    // @notice Batch update node scores from AI analysis
    function batchUpdateNodeScores(address[] calldata nodes, uint256[] calldata scores)
        external
        onlyRole(ORACLE_MANAGER_ROLE)
    {
        require(nodes.length == scores.length, "Array length mismatch");

        for (uint256 i = 0; i < nodes.length; i++) {
            require(scores[i] <= 100, "Score must be 0-100");
            nodeScores[nodes[i]] = scores[i];
            emit NodeScoreUpdated(nodes[i], scores[i]);
        }
    }

    // @notice Get demand forecast for specific task type
    // @param taskId Task identifier to get demand prediction for
    // @return demandScore Predicted demand (0-100 scale)
    // @return urgency Task urgency score (0-100 scale)
    // @return confidence Confidence in prediction
    function getDemandForecast(bytes32 taskId)
        external
        view
        returns (uint256 demandScore, uint256 urgency, uint256 confidence)
    {
        TaskDemand memory demand = taskDemandPredictions[taskId];
        
        if (demand.timestamp > 0 && block.timestamp - demand.timestamp < 1 hours) {
            // Return AI prediction if recent
            return (demand.demandScore, demand.urgency, 85);
        } else {
            // Return default values if no recent prediction
            return (50, 50, 60);
        }
    }

    // @notice Get current pricing predictions
    // @return basePriceMultiplier Base price multiplier (50-200%)
    // @return demandMultiplier Demand-based multiplier (50-300%)
    // @return lastUpdate Timestamp of last update
    function getPricingPrediction() external view returns (uint256 basePriceMultiplier, uint256 demandMultiplier, uint256 lastUpdate) {
        PricingPrediction memory pricing = pricingPredictions;
        
        if (pricing.lastUpdate > 0 && block.timestamp - pricing.lastUpdate < 2 hours) {
            return (pricing.basePriceMultiplier, pricing.demandMultiplier, pricing.lastUpdate);
        } else {
            // Return default pricing if no recent prediction
            return (100, 100, 0);
        }
    }
    
    // @notice Get node latency prediction
    // @param node Node address
    // @return latency Predicted latency in milliseconds
    function getNodeLatency(address node) external view returns (uint256 latency) {
        return nodeLatencies[node];
    }
    
    // @notice Get node energy efficiency score
    // @param node Node address
    // @return efficiency Energy efficiency score (0-100)
    function getNodeEnergyEfficiency(address node) external view returns (uint256 efficiency) {
        return nodeEnergyEfficiency[node];
    }
    
    // @notice Get comprehensive node metrics
    // @param node Node address
    // @return score AI computed efficiency score
    // @return latency Predicted latency in milliseconds
    // @return energyEfficiency Energy efficiency score
    function getNodeMetrics(address node) external view returns (uint256 score, uint256 latency, uint256 energyEfficiency) {
        return (nodeScores[node], nodeLatencies[node], nodeEnergyEfficiency[node]);
    }

    // @notice Update oracle configuration
    function updateOracleConfig(address _oracle, bytes32 _jobId, uint256 _fee) external onlyRole(ORACLE_MANAGER_ROLE) {
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

    function _processPrediction(bytes32 requestId, PredictionRequest memory request, bytes memory predictionData) internal {
        if (request.predictionType == PredictionType.NODE_SELECTION) {
            _processNodeSelection(predictionData);
        } else if (request.predictionType == PredictionType.TASK_DEMAND) {
            _processTaskDemand(request.taskId, predictionData);
        } else if (request.predictionType == PredictionType.RESOURCE_PRICING) {
            _processResourcePricing(predictionData);
        } else if (request.predictionType == PredictionType.LATENCY_FORECAST) {
            _processLatencyForecast(predictionData);
        } else if (request.predictionType == PredictionType.ENERGY_EFFICIENCY) {
            _processEnergyEfficiency(predictionData);
        }
        
        emit PredictionProcessed(requestId, request.predictionType);
    }
    
    // Process node selection predictions
    function _processNodeSelection(bytes memory predictionData) internal {
        try this._decodeNodePrediction(predictionData) returns (address[] memory nodes, uint256[] memory scores) {
            require(nodes.length == scores.length, "Array length mismatch");
            require(nodes.length <= 50, "Too many nodes in prediction");
            
            for (uint256 i = 0; i < nodes.length; i++) {
                if (nodes[i] != address(0) && scores[i] <= 100) {
                    nodeScores[nodes[i]] = scores[i];
                    emit NodeScoreUpdated(nodes[i], scores[i]);
                }
            }
        } catch {
            // Invalid prediction data format - ignore
        }
    }
    
    // Process task demand forecasting
    function _processTaskDemand(bytes32 taskId, bytes memory predictionData) internal {
        try this._decodeTaskDemand(predictionData) returns (uint256 demandScore, uint256 urgency) {
            require(demandScore <= 100 && urgency <= 100, "Invalid demand values");
            
            // Store demand prediction for task routing
            taskDemandPredictions[taskId] = TaskDemand({
                demandScore: demandScore,
                urgency: urgency,
                timestamp: block.timestamp
            });
            
            emit TaskDemandUpdated(taskId, demandScore, urgency);
        } catch {
            // Invalid prediction data format - ignore
        }
    }
    
    // Process resource pricing predictions
    function _processResourcePricing(bytes memory predictionData) internal {
        try this._decodePricingData(predictionData) returns (uint256 basePriceMultiplier, uint256 demandMultiplier) {
            require(basePriceMultiplier >= 50 && basePriceMultiplier <= 200, "Invalid base price multiplier");
            require(demandMultiplier >= 50 && demandMultiplier <= 300, "Invalid demand multiplier");
            
            pricingPredictions.basePriceMultiplier = basePriceMultiplier;
            pricingPredictions.demandMultiplier = demandMultiplier;
            pricingPredictions.lastUpdate = block.timestamp;
            
            emit PricingUpdated(basePriceMultiplier, demandMultiplier);
        } catch {
            // Invalid prediction data format - ignore
        }
    }
    
    // Process latency forecasting
    function _processLatencyForecast(bytes memory predictionData) internal {
        try this._decodeLatencyData(predictionData) returns (address[] memory nodes, uint256[] memory latencies) {
            require(nodes.length == latencies.length, "Array length mismatch");
            require(nodes.length <= 100, "Too many nodes in latency prediction");
            
            for (uint256 i = 0; i < nodes.length; i++) {
                if (nodes[i] != address(0) && latencies[i] <= 10000) { // Max 10 second latency
                    nodeLatencies[nodes[i]] = latencies[i];
                    emit NodeLatencyUpdated(nodes[i], latencies[i]);
                }
            }
        } catch {
            // Invalid prediction data format - ignore
        }
    }
    
    // Process energy efficiency predictions
    function _processEnergyEfficiency(bytes memory predictionData) internal {
        try this._decodeEnergyData(predictionData) returns (address[] memory nodes, uint256[] memory efficiencyScores) {
            require(nodes.length == efficiencyScores.length, "Array length mismatch");
            require(nodes.length <= 100, "Too many nodes in efficiency prediction");
            
            for (uint256 i = 0; i < nodes.length; i++) {
                if (nodes[i] != address(0) && efficiencyScores[i] <= 100) {
                    nodeEnergyEfficiency[nodes[i]] = efficiencyScores[i];
                    emit NodeEnergyEfficiencyUpdated(nodes[i], efficiencyScores[i]);
                }
            }
        } catch {
            // Invalid prediction data format - ignore
        }
    }
    
    // External decode functions for try-catch pattern
    function _decodeNodePrediction(bytes memory data) external pure returns (address[] memory, uint256[] memory) {
        return abi.decode(data, (address[], uint256[]));
    }
    
    function _decodeTaskDemand(bytes memory data) external pure returns (uint256, uint256) {
        return abi.decode(data, (uint256, uint256));
    }
    
    function _decodePricingData(bytes memory data) external pure returns (uint256, uint256) {
        return abi.decode(data, (uint256, uint256));
    }
    
    function _decodeLatencyData(bytes memory data) external pure returns (address[] memory, uint256[] memory) {
        return abi.decode(data, (address[], uint256[]));
    }
    
    function _decodeEnergyData(bytes memory data) external pure returns (address[] memory, uint256[] memory) {
        return abi.decode(data, (address[], uint256[]));
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
