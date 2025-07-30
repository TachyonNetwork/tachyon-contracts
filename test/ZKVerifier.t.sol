// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../src/ZKTaskVerifier.sol";
import "../src/RewardManager.sol";
import "../src/TachyonToken.sol";
import "../src/GreenVerifier.sol";
import "../src/AIOracle.sol";
import "./mocks/MockZKVerifier.sol";
import "./mocks/MockLinkToken.sol";
import "./mocks/MockOracle.sol";

contract ZKVerifierTest is Test {
    ZKTaskVerifier public zkVerifier;
    MockZKVerifier public mockZKVerifier;
    RewardManager public rewardManager;
    TachyonToken public tachyonToken;
    GreenVerifier public greenVerifier;
    AIOracle public aiOracle;

    MockLinkToken public mockLink;
    MockOracle public mockOracle;

    address public owner = address(0x1);
    address public node1 = address(0x2);
    address public validator = address(0x3);

    // Test task data
    bytes32 public testTaskId = keccak256("test-task-001");
    bytes32 public testResultHash = keccak256("task-result");
    uint256 public testTimestamp;

    function setUp() public {
        testTimestamp = block.timestamp;
        vm.startPrank(owner);

        // Deploy mock contracts
        mockLink = new MockLinkToken();
        mockOracle = new MockOracle();

        // Deploy core contracts
        deployContracts();

        // Setup roles
        setupRoles();

        // Fund test accounts
        fundAccounts();

        vm.stopPrank();
    }

    function deployContracts() internal {
        // Deploy TachyonToken
        TachyonToken tachyonImpl = new TachyonToken();
        bytes memory tachyonInitData = abi.encodeWithSelector(TachyonToken.initialize.selector, owner);
        ERC1967Proxy tachyonProxy = new ERC1967Proxy(address(tachyonImpl), tachyonInitData);
        tachyonToken = TachyonToken(payable(address(tachyonProxy)));

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
            bytes32("mockJobId"),
            0.1 * 10 ** 18,
            owner
        );
        ERC1967Proxy aiProxy = new ERC1967Proxy(address(aiImpl), aiInitData);
        aiOracle = AIOracle(address(aiProxy));

        // Deploy real ZKTaskVerifier
        ZKTaskVerifier zkImpl = new ZKTaskVerifier();
        bytes memory zkInitData = abi.encodeWithSelector(ZKTaskVerifier.initialize.selector, owner);
        ERC1967Proxy zkProxy = new ERC1967Proxy(address(zkImpl), zkInitData);
        zkVerifier = ZKTaskVerifier(address(zkProxy));

        // Deploy mock ZK verifier for testing
        mockZKVerifier = new MockZKVerifier();

        // Deploy RewardManager with mock ZK verifier
        RewardManager rewardImpl = new RewardManager();
        bytes memory rewardInitData = abi.encodeWithSelector(
            RewardManager.initialize.selector,
            address(tachyonToken),
            address(greenVerifier),
            address(aiOracle),
            address(mockZKVerifier), // Use mock for testing
            owner
        );
        ERC1967Proxy rewardProxy = new ERC1967Proxy(address(rewardImpl), rewardInitData);
        rewardManager = RewardManager(address(rewardProxy));
    }

    function setupRoles() internal {
        // Grant MINTER_ROLE to RewardManager
        tachyonToken.grantRole(tachyonToken.MINTER_ROLE(), address(rewardManager));

        // Grant VALIDATOR_ROLE
        rewardManager.grantRole(rewardManager.VALIDATOR_ROLE(), validator);

        // Setup AI Oracle node score
        aiOracle.grantRole(aiOracle.ORACLE_MANAGER_ROLE(), owner);
        aiOracle.updateNodeScore(node1, 85);
    }

    function fundAccounts() internal {
        // Transfer tokens to test nodes
        tachyonToken.transfer(node1, 10000 * 10 ** 18);
    }

    function testZKVerifierInitialization() public view {
        assertTrue(zkVerifier.isInitialized(), "ZK verifier should be initialized");
        assertEq(zkVerifier.owner(), owner, "Owner should be set correctly");
        assertTrue(zkVerifier.getVerificationKeyHash() != bytes32(0), "Verification key hash should be set");
    }

    function testMockZKVerifierValidProof() public view {
        // Generate valid test proof using mock
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input) =
            mockZKVerifier.generateValidProof(testTaskId, testResultHash, node1, testTimestamp);

        // Verify with mock verifier
        bool result = mockZKVerifier.verifyProof(a, b, c, input);
        assertTrue(result, "Valid proof should pass verification");
    }

    function testRewardManagerWithZKProof() public {
        vm.startPrank(node1);

        // Generate valid test proof
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input) =
            mockZKVerifier.generateValidProof(testTaskId, testResultHash, node1, testTimestamp);

        // Create ZK proof struct
        RewardManager.ZKProof memory proof = RewardManager.ZKProof({a: a, b: b, c: c, publicInputs: input});

        // Submit task completion with ZK proof
        rewardManager.submitTaskCompletion(testTaskId, testResultHash, proof);

        // Check task details
        (address taskNode, uint256 reward, RewardManager.ValidationStatus status, bool zkValidated) =
            rewardManager.getTaskDetails(testTaskId);

        assertEq(taskNode, node1, "Task should be assigned to node1");
        assertEq(uint256(status), uint256(RewardManager.ValidationStatus.VALIDATED), "Task should be validated");
        assertTrue(zkValidated, "Task should be ZK validated");
        assertTrue(reward > 0, "Reward should be calculated");

        vm.stopPrank();
    }

    function testInvalidZKProofRejection() public {
        vm.startPrank(node1);

        // Create invalid proof (wrong magic number)
        uint256[2] memory a = [uint256(99), uint256(100)]; // Invalid magic number
        uint256[2][2] memory b = [[uint256(1), uint256(2)], [uint256(3), uint256(4)]];
        uint256[2] memory c = [uint256(5), uint256(6)];
        uint256[4] memory input = [uint256(testTaskId), uint256(testResultHash), uint256(uint160(node1)), testTimestamp];

        RewardManager.ZKProof memory proof = RewardManager.ZKProof({a: a, b: b, c: c, publicInputs: input});

        // Set mock to reject this proof
        mockZKVerifier.setDefaultResult(false);

        // Submit task completion with invalid proof
        rewardManager.submitTaskCompletion(testTaskId, testResultHash, proof);

        // Check task was rejected
        (,, RewardManager.ValidationStatus status, bool zkValidated) = rewardManager.getTaskDetails(testTaskId);

        assertEq(uint256(status), uint256(RewardManager.ValidationStatus.REJECTED), "Task should be rejected");
        assertFalse(zkValidated, "Task should not be ZK validated");

        vm.stopPrank();
    }

    function testZKProofWithGreenMultiplier() public {
        // Setup green certificate for node1
        uint256 oraclePrivateKey = 999; // Private key for oracle
        address oracleAddress = vm.addr(oraclePrivateKey);

        vm.startPrank(owner);
        greenVerifier.grantRole(greenVerifier.VERIFIER_ROLE(), owner);
        greenVerifier.grantRole(greenVerifier.ORACLE_ROLE(), oracleAddress);
        vm.stopPrank();

        // Create certificate data and sign it with oracle's key
        uint256 energyType = 1; // Solar
        uint256 percentage = 80; // 80% renewable
        bytes memory certData = "green-cert-data";

        // Create the message hash that matches GreenVerifier's expectation
        bytes32 messageHash = keccak256(abi.encodePacked(node1, energyType, percentage, certData));

        // GreenVerifier uses MessageHashUtils.toEthSignedMessageHash internally,
        // and vm.sign ALSO adds the prefix, so we need to sign the already-prefixed hash
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Submit certificate as node1
        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(energyType, percentage, certData, signature);
        vm.stopPrank();

        // Verify certificate as owner
        vm.startPrank(owner);
        greenVerifier.verifyCertificate(node1, true);
        vm.stopPrank();

        vm.startPrank(node1);

        // Generate valid test proof
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input) =
            mockZKVerifier.generateValidProof(testTaskId, testResultHash, node1, testTimestamp);

        RewardManager.ZKProof memory proof = RewardManager.ZKProof({a: a, b: b, c: c, publicInputs: input});

        // Submit task completion
        rewardManager.submitTaskCompletion(testTaskId, testResultHash, proof);

        // Check reward includes green multiplier
        (, uint256 reward,, bool zkValidated) = rewardManager.getTaskDetails(testTaskId);

        assertTrue(zkValidated, "Task should be ZK validated");

        // Base reward is 100 * 10**18
        // Green multiplier calculation:
        // - Base: 100 + (80 * (200-100) / 100) = 180
        // - Green score 88 >= 75: additional 5% = 180 * 105 / 100 = 189
        // AI score bonus (85 > 80) = 1.1x
        // Final: 100 * 10**18 * 189 / 100 * 110 / 100 = 207,900 * 10**18
        uint256 expectedReward = 207900000000000000000;
        assertEq(reward, expectedReward, "Reward should include green multiplier and bonuses");

        vm.stopPrank();
    }

    function testClaimZKValidatedRewards() public {
        vm.startPrank(node1);

        // Submit multiple tasks with ZK proofs
        for (uint256 i = 0; i < 3; i++) {
            bytes32 taskId = keccak256(abi.encode("task", i));
            bytes32 resultHash = keccak256(abi.encode("result", i));

            (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input) =
                mockZKVerifier.generateValidProof(taskId, resultHash, node1, block.timestamp);

            RewardManager.ZKProof memory proof = RewardManager.ZKProof({a: a, b: b, c: c, publicInputs: input});

            rewardManager.submitTaskCompletion(taskId, resultHash, proof);
        }

        // Check pending rewards
        (, uint256 pendingAmount,,) = rewardManager.getNodeStats(node1);
        assertTrue(pendingAmount > 0, "Should have pending rewards");

        // Claim rewards
        uint256 balanceBefore = tachyonToken.balanceOf(node1);
        rewardManager.claimRewards();
        uint256 balanceAfter = tachyonToken.balanceOf(node1);

        assertEq(balanceAfter - balanceBefore, pendingAmount, "Should receive pending rewards");

        // Check pending is now 0
        (, uint256 newPending,,) = rewardManager.getNodeStats(node1);
        assertEq(newPending, 0, "Pending rewards should be 0 after claim");

        vm.stopPrank();
    }

    function testRealZKVerifierStructure() public {
        // Test the real ZK verifier has proper structure
        assertTrue(zkVerifier.isInitialized(), "Real verifier should be initialized");

        // Verification key hash should be deterministic
        bytes32 keyHash = zkVerifier.getVerificationKeyHash();
        assertTrue(keyHash != bytes32(0), "Key hash should be set");

        // Test with dummy proof (will fail but tests the structure)
        uint256[2] memory a = [uint256(1), uint256(2)];
        uint256[2][2] memory b = [[uint256(3), uint256(4)], [uint256(5), uint256(6)]];
        uint256[2] memory c = [uint256(7), uint256(8)];
        uint256[4] memory input = [uint256(9), uint256(10), uint256(11), uint256(12)];

        // This will revert due to invalid proof, but that's expected
        vm.expectRevert();
        zkVerifier.verifyProof(a, b, c, input);
    }
}
