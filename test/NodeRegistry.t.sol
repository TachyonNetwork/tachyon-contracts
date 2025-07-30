// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../src/NodeRegistry.sol";
import "../src/TachyonToken.sol";
import "../src/GreenVerifier.sol";
import "../src/AIOracle.sol";
import "./mocks/MockLinkToken.sol";
import "./mocks/MockOracle.sol";

contract NodeRegistryTest is Test {
    NodeRegistry public nodeRegistry;
    TachyonToken public tachyonToken;
    GreenVerifier public greenVerifier;
    AIOracle public aiOracle;
    MockLinkToken public mockLink;
    MockOracle public mockOracle;

    address public owner = address(0x1);
    address public attestor = address(0x2);
    address public slasher = address(0x3);
    address public node1 = address(0x4);

    uint256 public attestorPrivateKey = 888;

    event NodeRegistered(address indexed node, uint256 stake, bytes32 attestationHash);
    event NodeUnregistered(address indexed node, uint256 returnedStake);
    event NodeSlashed(address indexed node, uint256 slashedAmount, string reason);

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

        // Setup roles
        address attestorAddress = vm.addr(attestorPrivateKey);
        nodeRegistry.grantRole(nodeRegistry.ATTESTOR_ROLE(), attestorAddress);
        nodeRegistry.grantRole(nodeRegistry.SLASHER_ROLE(), slasher);

        // Mint tokens to test node
        tachyonToken.mint(node1, 10000 * 10**18);

        vm.stopPrank();
    }

    function testInitialization() public view {
        assertEq(address(nodeRegistry.tachyonToken()), address(tachyonToken));
        assertEq(address(nodeRegistry.greenVerifier()), address(greenVerifier));
        assertEq(address(nodeRegistry.aiOracle()), address(aiOracle));
        assertEq(nodeRegistry.owner(), owner);
        assertTrue(nodeRegistry.hasRole(nodeRegistry.ATTESTOR_ROLE(), vm.addr(attestorPrivateKey)));
        assertTrue(nodeRegistry.hasRole(nodeRegistry.SLASHER_ROLE(), slasher));
    }

    function testRegisterNode() public {
        vm.startPrank(node1);

        // Create node capabilities
        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.LAPTOP_CONSUMER,
            cpuCores: 8,
            cpuFrequencyMHz: 3200,
            ramGB: 16,
            storageGB: 512,
            gpuMemoryGB: 0,
            bandwidth: 100,
            uptime: 85,
            batteryCapacityWh: 5000,
            networkLatencyMs: 50,
            hasGPU: false,
            hasTPU: false,
            isMobile: true,
            supportsContainers: true,
            supportsKubernetes: false,
            isDataCenterHosted: false,
            gpuModel: "",
            operatingSystem: "Ubuntu 22.04"
        });

        bytes memory attestationData = "node-attestation-data";
        
        // Create attestation hash and sign it
        bytes32 attestationHash = keccak256(abi.encode(node1, capabilities, attestationData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(attestationHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Approve required stake (200e18 for LAPTOP_CONSUMER)
        uint256 requiredStake = 200 * 10**18;
        tachyonToken.approve(address(nodeRegistry), requiredStake);

        vm.expectEmit(true, false, false, true);
        emit NodeRegistered(node1, requiredStake, attestationHash);

        nodeRegistry.registerNode(capabilities, attestationData, signature);

        // Verify node was registered
        (
            uint256 stake,
            uint256 registrationTime,
            uint256 lastActiveTime,
            uint256 totalEarnings,
            uint256 lastMaintenanceTime,
            uint128 tasksCompleted,
            uint128 tasksDisputed,
            uint64 reputation,
            uint32 activeTasks,
            ,,,
            bool registered,
            bool isGreen,
            bool isPowerSaving
        ) = nodeRegistry.nodes(node1);

        assertEq(stake, requiredStake);
        assertTrue(registrationTime > 0);
        assertTrue(lastActiveTime > 0);
        assertEq(totalEarnings, 0);
        assertTrue(lastMaintenanceTime > 0);
        assertEq(tasksCompleted, 0);
        assertEq(tasksDisputed, 0);
        assertEq(reputation, 50); // Default reputation
        assertEq(activeTasks, 0);
        assertTrue(registered);
        assertFalse(isGreen);
        assertFalse(isPowerSaving); // Power saving starts disabled

        vm.stopPrank();
    }

    function testRegisterNodeInsufficientSpecs() public {
        vm.startPrank(node1);

        // Create node capabilities with insufficient specs
        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.LAPTOP_CONSUMER,
            cpuCores: 2, // Too low (needs >= 4)
            cpuFrequencyMHz: 2000,
            ramGB: 4, // Too low (needs >= 8)
            storageGB: 128, // Too low (needs >= 256)
            gpuMemoryGB: 0,
            bandwidth: 25, // Too low (needs >= 50)
            uptime: 85,
            batteryCapacityWh: 5000,
            networkLatencyMs: 50,
            hasGPU: false,
            hasTPU: false,
            isMobile: true,
            supportsContainers: true,
            supportsKubernetes: false,
            isDataCenterHosted: false,
            gpuModel: "",
            operatingSystem: "Ubuntu 22.04"
        });

        bytes memory attestationData = "node-attestation-data";
        
        bytes32 attestationHash = keccak256(abi.encode(node1, capabilities, attestationData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(attestationHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 requiredStake = 200 * 10**18;
        tachyonToken.approve(address(nodeRegistry), requiredStake);

        vm.expectRevert("Insufficient specs");
        nodeRegistry.registerNode(capabilities, attestationData, signature);

        vm.stopPrank();
    }

    function testRegisterNodeInvalidSignature() public {
        vm.startPrank(node1);

        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.LAPTOP_CONSUMER,
            cpuCores: 8,
            cpuFrequencyMHz: 3200,
            ramGB: 16,
            storageGB: 512,
            gpuMemoryGB: 0,
            bandwidth: 100,
            uptime: 85,
            batteryCapacityWh: 5000,
            networkLatencyMs: 50,
            hasGPU: false,
            hasTPU: false,
            isMobile: true,
            supportsContainers: true,
            supportsKubernetes: false,
            isDataCenterHosted: false,
            gpuModel: "",
            operatingSystem: "Ubuntu 22.04"
        });

        bytes memory attestationData = "node-attestation-data";
        
        // Sign with wrong private key
        bytes32 attestationHash = keccak256(abi.encode(node1, capabilities, attestationData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(attestationHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(999, ethSignedMessageHash); // Wrong key
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        uint256 requiredStake = 200 * 10**18;
        tachyonToken.approve(address(nodeRegistry), requiredStake);

        vm.expectRevert("Invalid signature");
        nodeRegistry.registerNode(capabilities, attestationData, invalidSignature);

        vm.stopPrank();
    }

    function testGetTotalNodes() public view {
        uint256 totalNodes = nodeRegistry.totalNodes();
        assertEq(totalNodes, 0);
    }

    function testSlashingPercentage() public view {
        uint256 percentage = nodeRegistry.slashingPercentage();
        assertEq(percentage, 10); // Default 10%
    }

    function testInactivityThreshold() public view {
        uint256 threshold = nodeRegistry.inactivityThreshold();
        assertEq(threshold, 7 days);
    }

    function testMobilePowerSaveThreshold() public view {
        uint256 threshold = nodeRegistry.mobilePowerSaveThreshold();
        assertEq(threshold, 20);
    }

    function testDeviceProfileLaptopConsumer() public view {
        (
            uint256 minStakeRequired,
            uint128 maxConcurrentTasks,
            uint128 minCpuCores,
            uint128 minRamGB,
            uint128 minStorageGB,
            uint64 minBandwidthMbps,
            uint32 powerEfficiencyScore,
            uint32 reliabilityScore,
            bool supportsBatchProcessing,
            bool supportsGPUCompute,
            bool supportsLowLatency
        ) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.LAPTOP_CONSUMER);

        assertEq(minStakeRequired, 200 * 10**18);
        assertEq(maxConcurrentTasks, 5);
        assertEq(minCpuCores, 4);
        assertEq(minRamGB, 8);
        assertEq(minStorageGB, 256);
        assertEq(minBandwidthMbps, 50);
        assertEq(powerEfficiencyScore, 70);
        assertEq(reliabilityScore, 75);
        assertTrue(supportsBatchProcessing);
        assertTrue(supportsGPUCompute);
        assertTrue(supportsLowLatency);
    }

    function testIsMobileDevice() public view {
        assertTrue(nodeRegistry.isMobileDevice(NodeRegistry.NodeDeviceType.SMARTPHONE));
        assertTrue(nodeRegistry.isMobileDevice(NodeRegistry.NodeDeviceType.TABLET));
        assertTrue(nodeRegistry.isMobileDevice(NodeRegistry.NodeDeviceType.LAPTOP_CONSUMER));
        assertFalse(nodeRegistry.isMobileDevice(NodeRegistry.NodeDeviceType.SERVER_TOWER));
    }

    function testIsServerDevice() public view {
        assertTrue(nodeRegistry.isServerDevice(NodeRegistry.NodeDeviceType.SERVER_TOWER));
        assertTrue(nodeRegistry.isServerDevice(NodeRegistry.NodeDeviceType.SERVER_RACK_2U));
        assertFalse(nodeRegistry.isServerDevice(NodeRegistry.NodeDeviceType.SMARTPHONE));
        assertFalse(nodeRegistry.isServerDevice(NodeRegistry.NodeDeviceType.LAPTOP_CONSUMER));
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);
        
        nodeRegistry.pause();
        assertTrue(nodeRegistry.paused());
        
        vm.stopPrank();
        
        // Should not be able to register when paused
        vm.startPrank(node1);
        
        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.SMARTPHONE,
            cpuCores: 4,
            cpuFrequencyMHz: 2400,
            ramGB: 4,
            storageGB: 64,
            gpuMemoryGB: 0,
            bandwidth: 25,
            uptime: 90,
            batteryCapacityWh: 3000,
            networkLatencyMs: 100,
            hasGPU: false,
            hasTPU: false,
            isMobile: true,
            supportsContainers: false,
            supportsKubernetes: false,
            isDataCenterHosted: false,
            gpuModel: "",
            operatingSystem: "Android 13"
        });

        vm.expectRevert(); // Generic revert due to paused state
        nodeRegistry.registerNode(capabilities, "test", "signature");
        
        vm.stopPrank();
        
        vm.startPrank(owner);
        nodeRegistry.unpause();
        assertFalse(nodeRegistry.paused());
        vm.stopPrank();
    }

    function testAccessControl() public {
        // Non-attestor address should not be trusted for signatures
        address nonAttestor = address(0x999);
        
        vm.startPrank(node1);

        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.LAPTOP_CONSUMER,
            cpuCores: 8,
            cpuFrequencyMHz: 3200,
            ramGB: 16,
            storageGB: 512,
            gpuMemoryGB: 0,
            bandwidth: 100,
            uptime: 85,
            batteryCapacityWh: 5000,
            networkLatencyMs: 50,
            hasGPU: false,
            hasTPU: false,
            isMobile: true,
            supportsContainers: true,
            supportsKubernetes: false,
            isDataCenterHosted: false,
            gpuModel: "",
            operatingSystem: "Ubuntu 22.04"
        });

        bytes memory attestationData = "node-attestation-data";
        bytes32 attestationHash = keccak256(abi.encode(node1, capabilities, attestationData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(attestationHash);
        
        // Sign with non-attestor key
        uint256 nonAttestorKey = 777;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nonAttestorKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 requiredStake = 200 * 10**18;
        tachyonToken.approve(address(nodeRegistry), requiredStake);

        vm.expectRevert("Invalid signature");
        nodeRegistry.registerNode(capabilities, attestationData, signature);

        vm.stopPrank();
    }
}