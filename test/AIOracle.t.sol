// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/AIOracle.sol";
import "./mocks/MockLinkToken.sol";
import "./mocks/MockOracle.sol";

contract AIOracleTest is Test {
    AIOracle public aiOracle;
    MockLinkToken public mockLink;
    MockOracle public mockOracle;

    address public owner = address(0x1);
    address public consumer = address(0x2);
    address public oracleManager = address(0x3);
    address public node1 = address(0x4);
    address public node2 = address(0x5);

    bytes32 public constant TEST_JOB_ID = bytes32("test-job-id");
    uint256 public constant TEST_FEE = 0.1 * 10 ** 18;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        mockLink = new MockLinkToken();
        mockOracle = new MockOracle();

        // Deploy AIOracle
        AIOracle aiImpl = new AIOracle();
        bytes memory initData = abi.encodeWithSelector(
            AIOracle.initialize.selector, address(mockLink), address(mockOracle), TEST_JOB_ID, TEST_FEE, owner
        );
        ERC1967Proxy aiProxy = new ERC1967Proxy(address(aiImpl), initData);
        aiOracle = AIOracle(address(aiProxy));

        // Setup roles
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), consumer);
        aiOracle.grantRole(aiOracle.ORACLE_MANAGER_ROLE(), oracleManager);

        // Fund oracle with LINK
        mockLink.transfer(address(aiOracle), 10 * 10 ** 18);

        vm.stopPrank();
    }

    function testInitialization() public view {
        assertEq(aiOracle.owner(), owner);
        assertTrue(aiOracle.hasRole(aiOracle.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(aiOracle.hasRole(aiOracle.AI_CONSUMER_ROLE(), consumer));
        assertTrue(aiOracle.hasRole(aiOracle.ORACLE_MANAGER_ROLE(), oracleManager));
        assertEq(aiOracle.getLinkBalance(), 10 * 10 ** 18);
    }

    function testRequestPrediction() public {
        vm.startPrank(consumer);

        bytes32 taskId = keccak256("test-task");
        bytes memory inputData = "test-input";

        bytes32 requestId = aiOracle.requestPrediction(AIOracle.PredictionType.NODE_SELECTION, taskId, inputData);

        assertTrue(requestId != bytes32(0));

        // Check pending request was stored
        (AIOracle.PredictionType predictionType, bytes32 storedTaskId, address requester, uint256 timestamp) =
            aiOracle.pendingRequests(requestId);

        assertEq(uint256(predictionType), uint256(AIOracle.PredictionType.NODE_SELECTION));
        assertEq(storedTaskId, taskId);
        assertEq(requester, consumer);
        assertTrue(timestamp > 0);

        vm.stopPrank();
    }

    function testUpdateNodeScore() public {
        vm.startPrank(oracleManager);

        aiOracle.updateNodeScore(node1, 95);
        assertEq(aiOracle.nodeScores(node1), 95);

        vm.stopPrank();
    }

    function testBatchUpdateNodeScores() public {
        address[] memory nodes = new address[](3);
        nodes[0] = node1;
        nodes[1] = node2;
        nodes[2] = address(0x6);

        uint256[] memory scores = new uint256[](3);
        scores[0] = 88;
        scores[1] = 92;
        scores[2] = 76;

        vm.startPrank(oracleManager);
        aiOracle.batchUpdateNodeScores(nodes, scores);

        for (uint256 i = 0; i < nodes.length; i++) {
            assertEq(aiOracle.nodeScores(nodes[i]), scores[i]);
        }

        vm.stopPrank();
    }

    function testGetOptimalNodes() public view {
        bytes memory taskRequirements = "";
        (address[] memory nodes, uint256[] memory scores) = aiOracle.getOptimalNodes(taskRequirements);

        // Should return empty arrays for now (stub implementation)
        assertEq(nodes.length, 10);
        assertEq(scores.length, 10);

        // All should be zero addresses and scores
        for (uint256 i = 0; i < nodes.length; i++) {
            assertEq(nodes[i], address(0));
            assertEq(scores[i], 0);
        }
    }

    function testGetDemandForecastDefault() public view {
        bytes32 taskId = keccak256("test-task");

        // Test default values (no prediction)
        (uint256 demand, uint256 urgency, uint256 confidence) = aiOracle.getDemandForecast(taskId);
        assertEq(demand, 50);
        assertEq(urgency, 50);
        assertEq(confidence, 60);
    }

    function testGetPricingPredictionDefault() public view {
        // Test default pricing (no prediction)
        (uint256 basePrice, uint256 demandMultiplier, uint256 lastUpdate) = aiOracle.getPricingPrediction();
        assertEq(basePrice, 100);
        assertEq(demandMultiplier, 100);
        assertEq(lastUpdate, 0);
    }

    function testGetNodeLatency() public view {
        uint256 latency = aiOracle.getNodeLatency(node1);
        assertEq(latency, 0); // Should be 0 by default
    }

    function testGetNodeEnergyEfficiency() public view {
        uint256 efficiency = aiOracle.getNodeEnergyEfficiency(node1);
        assertEq(efficiency, 0); // Should be 0 by default
    }

    function testGetNodeMetrics() public view {
        (uint256 score, uint256 latency, uint256 energyEfficiency) = aiOracle.getNodeMetrics(node1);
        assertEq(score, 0);
        assertEq(latency, 0);
        assertEq(energyEfficiency, 0);
    }

    function testUpdateNodeScoreInvalidScore() public {
        vm.startPrank(oracleManager);

        vm.expectRevert("Score must be 0-100");
        aiOracle.updateNodeScore(node1, 101); // Invalid score > 100

        vm.stopPrank();
    }

    function testBatchUpdateNodeScoresArrayMismatch() public {
        address[] memory nodes = new address[](2);
        nodes[0] = node1;
        nodes[1] = node2;

        uint256[] memory scores = new uint256[](3); // Different length
        scores[0] = 88;
        scores[1] = 92;
        scores[2] = 76;

        vm.startPrank(oracleManager);
        vm.expectRevert("Array length mismatch");
        aiOracle.batchUpdateNodeScores(nodes, scores);
        vm.stopPrank();
    }

    function testBatchUpdateNodeScoresInvalidScore() public {
        address[] memory nodes = new address[](2);
        nodes[0] = node1;
        nodes[1] = node2;

        uint256[] memory scores = new uint256[](2);
        scores[0] = 88;
        scores[1] = 150; // Invalid score > 100

        vm.startPrank(oracleManager);
        vm.expectRevert("Score must be 0-100");
        aiOracle.batchUpdateNodeScores(nodes, scores);
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);

        aiOracle.pause();
        assertTrue(aiOracle.paused());

        // Should not be able to request predictions when paused
        vm.stopPrank();
        vm.startPrank(consumer);
        vm.expectRevert(); // Just expect any revert due to paused state
        aiOracle.requestPrediction(AIOracle.PredictionType.NODE_SELECTION, bytes32(0), "");
        vm.stopPrank();

        vm.startPrank(owner);
        aiOracle.unpause();
        assertFalse(aiOracle.paused());
        vm.stopPrank();
    }

    function testAccessControl() public {
        // Non-consumer should not be able to request predictions
        vm.startPrank(address(0x999));
        vm.expectRevert();
        aiOracle.requestPrediction(AIOracle.PredictionType.NODE_SELECTION, bytes32(0), "");
        vm.stopPrank();

        // Non-oracle-manager should not be able to update scores
        vm.startPrank(address(0x999));
        vm.expectRevert();
        aiOracle.updateNodeScore(node1, 50);
        vm.stopPrank();
    }

    function testUpdateOracleConfig() public {
        address newOracle = address(0x123);
        bytes32 newJobId = bytes32("new-job-id");
        uint256 newFee = 0.2 * 10 ** 18;

        vm.startPrank(oracleManager);
        aiOracle.updateOracleConfig(newOracle, newJobId, newFee);
        vm.stopPrank();

        // Note: We can't directly verify the internal state change
        // but we can verify the function executed without reverting
    }

    function testWithdrawLink() public {
        uint256 initialBalance = mockLink.balanceOf(owner);
        uint256 contractBalance = aiOracle.getLinkBalance();

        vm.startPrank(owner);
        aiOracle.withdrawLink();
        vm.stopPrank();

        uint256 finalBalance = mockLink.balanceOf(owner);
        assertEq(finalBalance - initialBalance, contractBalance);
        assertEq(aiOracle.getLinkBalance(), 0);
    }

    function testVersion() public view {
        string memory version = aiOracle.version();
        assertEq(version, "1.0.0");
    }

    function testMinConfidenceConstant() public view {
        uint256 minConfidence = aiOracle.MIN_CONFIDENCE();
        assertEq(minConfidence, 70);
    }

    function testOracleCooldownConstant() public view {
        uint256 cooldown = aiOracle.ORACLE_COOLDOWN();
        assertEq(cooldown, 5 minutes);
    }
}
