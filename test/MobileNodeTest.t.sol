// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/NodeRegistry.sol";
import "../src/TachyonToken.sol";
import "../src/GreenVerifier.sol";
import "../src/AIOracle.sol";

contract MobileNodeTest is Test {
    NodeRegistry public nodeRegistry;
    TachyonToken public tachyonToken;
    GreenVerifier public greenVerifier;
    AIOracle public aiOracle;
    
    address public owner = makeAddr("owner");
    address public mobileUser = makeAddr("mobileUser");
    address public serverUser = makeAddr("serverUser");
    uint256 public attestorKey = 1;
    address public attestor = vm.addr(attestorKey);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy contracts with proxies
        TachyonToken tachyonImpl = new TachyonToken();
        bytes memory tachyonInitData = abi.encodeWithSelector(
            TachyonToken.initialize.selector,
            owner
        );
        ERC1967Proxy tachyonProxy = new ERC1967Proxy(
            address(tachyonImpl),
            tachyonInitData
        );
        tachyonToken = TachyonToken(payable(address(tachyonProxy)));
        
        GreenVerifier greenImpl = new GreenVerifier();
        bytes memory greenInitData = abi.encodeWithSelector(
            GreenVerifier.initialize.selector,
            owner
        );
        ERC1967Proxy greenProxy = new ERC1967Proxy(
            address(greenImpl),
            greenInitData
        );
        greenVerifier = GreenVerifier(address(greenProxy));
        
        AIOracle aiImpl = new AIOracle();
        bytes memory aiInitData = abi.encodeWithSelector(
            AIOracle.initialize.selector,
            address(0), // mock LINK token
            address(0), // mock oracle
            bytes32(0), // mock job id
            0,         // mock fee
            owner
        );
        ERC1967Proxy aiProxy = new ERC1967Proxy(
            address(aiImpl),
            aiInitData
        );
        aiOracle = AIOracle(address(aiProxy));
        
        NodeRegistry nodeImpl = new NodeRegistry();
        bytes memory nodeInitData = abi.encodeWithSelector(
            NodeRegistry.initialize.selector,
            address(tachyonToken),
            address(greenVerifier),
            address(aiOracle),
            owner
        );
        ERC1967Proxy nodeProxy = new ERC1967Proxy(
            address(nodeImpl),
            nodeInitData
        );
        nodeRegistry = NodeRegistry(address(nodeProxy));
        
        // Grant attestor role
        nodeRegistry.grantRole(nodeRegistry.ATTESTOR_ROLE(), attestor);
        
        // Grant admin role to NodeRegistry on AIOracle so it can grant AI_CONSUMER_ROLE to nodes
        aiOracle.grantRole(aiOracle.DEFAULT_ADMIN_ROLE(), address(nodeRegistry));
        
        // Mint tokens to users
        tachyonToken.mint(mobileUser, 1000 * 10**18);
        tachyonToken.mint(serverUser, 100000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testDeviceProfilesInitialized() public {
        // Test smartphone profile
        (uint256 minStake, uint256 maxTasks, , , , , , , , , ) = 
            nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.SMARTPHONE);
        
        assertEq(minStake, 10 * 10**18, "Smartphone should require 10 TACH");
        assertEq(maxTasks, 1, "Smartphone should handle 1 concurrent task");
        
        // Test server profile
        (minStake, maxTasks, , , , , , , , , ) = 
            nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.SERVER_RACK_2U);
        
        assertEq(minStake, 12000 * 10**18, "Server should require 12000 TACH");
        assertEq(maxTasks, 100, "Server should handle 100 concurrent tasks");
        
        console.log("[PASS] Device profiles initialized correctly");
    }
    
    function testSmartphoneRegistration() public {
        vm.startPrank(mobileUser);
        
        // Approve tokens (smartphone needs only 10 TACH)
        tachyonToken.approve(address(nodeRegistry), 10 * 10**18);
        
        // Create smartphone capabilities
        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.SMARTPHONE,
            cpuCores: 8,
            cpuFrequencyMHz: 2800,
            ramGB: 8,
            storageGB: 128,
            gpuMemoryGB: 0,
            gpuModel: "Adreno 740",
            hasGPU: true,
            hasTPU: false,
            bandwidth: 50,
            uptime: 80,
            isMobile: true,
            batteryCapacityWh: 20, // 20Wh battery
            operatingSystem: "Android 14",
            supportsContainers: false,
            supportsKubernetes: false,
            networkLatencyMs: 30,
            isDataCenterHosted: false
        });
        
        // Mock attestation signature
        bytes memory attestationData = abi.encode("smartphone_attestation");
        bytes32 attestationHash = keccak256(abi.encode(mobileUser, capabilities, attestationData));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", attestationHash));
        
        vm.stopPrank();
        
        // Create signature from attestor
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.startPrank(mobileUser);
        
        // Register smartphone node
        nodeRegistry.registerNode(capabilities, attestationData, signature);
        
        // Verify registration
        (NodeRegistry.NodeInfo memory nodeInfo,,) = nodeRegistry.getNodeDetails(mobileUser);
        assertTrue(nodeInfo.registered, "Node should be registered");
        assertEq(nodeInfo.stake, 10 * 10**18, "Stake should be 10 TACH");
        assertEq(uint8(nodeInfo.capabilities.deviceType), uint8(NodeRegistry.NodeDeviceType.SMARTPHONE));
        assertTrue(nodeInfo.capabilities.isMobile, "Should be marked as mobile");
        
        vm.stopPrank();
        
        console.log("[PASS] Smartphone registration successful");
        console.log("   - Stake: 10 TACH");
        console.log("   - Max concurrent tasks: 1");
        console.log("   - Battery capacity: 20Wh");
    }
    
    function testRaspberryPiRegistration() public {
        vm.startPrank(mobileUser);
        
        // Raspberry Pi 5 needs 35 TACH
        tachyonToken.approve(address(nodeRegistry), 35 * 10**18);
        
        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.RASPBERRY_PI_5,
            cpuCores: 4,
            cpuFrequencyMHz: 2400,
            ramGB: 8,
            storageGB: 64,
            gpuMemoryGB: 0,
            gpuModel: "VideoCore VII",
            hasGPU: false,
            hasTPU: false,
            bandwidth: 100,
            uptime: 95,
            isMobile: false,
            batteryCapacityWh: 0,
            operatingSystem: "Raspberry Pi OS",
            supportsContainers: true,
            supportsKubernetes: false,
            networkLatencyMs: 10,
            isDataCenterHosted: false
        });
        
        bytes memory attestationData = abi.encode("rpi5_attestation");
        bytes32 attestationHash = keccak256(abi.encode(mobileUser, capabilities, attestationData));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", attestationHash));
        
        vm.stopPrank();
        
        // Sign with attestor
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.startPrank(mobileUser);
        nodeRegistry.registerNode(capabilities, attestationData, signature);
        
        (NodeRegistry.NodeInfo memory nodeInfo,,) = nodeRegistry.getNodeDetails(mobileUser);
        assertEq(nodeInfo.stake, 35 * 10**18, "RPi5 should stake 35 TACH");
        assertEq(nodeInfo.deviceProfile.maxConcurrentTasks, 3, "RPi5 should handle 3 tasks");
        
        vm.stopPrank();
        
        console.log("[PASS] Raspberry Pi 5 registration successful");
        console.log("   - Stake: 35 TACH");
        console.log("   - Max concurrent tasks: 3");
    }
    
    function testMobilePowerSaving() public {
        // First register a smartphone
        testSmartphoneRegistration();
        
        vm.startPrank(mobileUser);
        
        // Test power saving toggle
        nodeRegistry.togglePowerSavingMode();
        
        (NodeRegistry.NodeInfo memory nodeInfo,,) = nodeRegistry.getNodeDetails(mobileUser);
        assertTrue(nodeInfo.isPowerSaving, "Power saving should be enabled");
        
        // Test that node cannot handle tasks in power saving mode
        bool canHandle = nodeRegistry.canNodeHandleTask(mobileUser);
        assertFalse(canHandle, "Node in power saving mode cannot handle tasks");
        
        // Toggle back
        nodeRegistry.togglePowerSavingMode();
        (nodeInfo,,) = nodeRegistry.getNodeDetails(mobileUser);
        assertFalse(nodeInfo.isPowerSaving, "Power saving should be disabled");
        
        vm.stopPrank();
        
        console.log("[PASS] Mobile power saving functionality works");
    }
    
    function testBatteryAlert() public {
        // Register smartphone independently
        vm.startPrank(mobileUser);
        
        // Approve tokens (smartphone needs only 10 TACH)
        tachyonToken.approve(address(nodeRegistry), 10 * 10**18);
        
        // Create smartphone capabilities
        NodeRegistry.NodeCapabilities memory capabilities = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.SMARTPHONE,
            cpuCores: 8,
            cpuFrequencyMHz: 2800,
            ramGB: 8,
            storageGB: 128,
            gpuMemoryGB: 0,
            gpuModel: "Adreno 740",
            hasGPU: true,
            hasTPU: false,
            bandwidth: 50,
            uptime: 80,
            isMobile: true,
            batteryCapacityWh: 20,
            operatingSystem: "Android 14",
            supportsContainers: false,
            supportsKubernetes: false,
            networkLatencyMs: 30,
            isDataCenterHosted: false
        });
        
        // Create signature
        bytes memory attestationData = abi.encode("battery_test_attestation");
        bytes32 attestationHash = keccak256(abi.encode(mobileUser, capabilities, attestationData));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", attestationHash));
        
        vm.stopPrank();
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.startPrank(mobileUser);
        
        // Register smartphone node
        nodeRegistry.registerNode(capabilities, attestationData, signature);
        
        // Verify registration and initial state
        (NodeRegistry.NodeInfo memory initialNodeInfo,,) = nodeRegistry.getNodeDetails(mobileUser);
        assertTrue(initialNodeInfo.registered, "Node should be registered");
        assertFalse(initialNodeInfo.isPowerSaving, "Power saving should initially be disabled");
        
        // Verify preconditions
        uint256 threshold = nodeRegistry.mobilePowerSaveThreshold();
        assertEq(threshold, 20, "Threshold should be 20");
        
        bool isSmartphoneMobile = nodeRegistry.isMobileDevice(NodeRegistry.NodeDeviceType.SMARTPHONE);
        assertTrue(isSmartphoneMobile, "SMARTPHONE should be classified as mobile");
        
        // Report low battery (15% - below 20% threshold)
        nodeRegistry.reportBatteryLevel(15);
        
        // Check that power saving was automatically enabled
        (NodeRegistry.NodeInfo memory updatedNodeInfo,,) = nodeRegistry.getNodeDetails(mobileUser);
        assertTrue(updatedNodeInfo.isPowerSaving, "Power saving should auto-enable on low battery");
        
        vm.stopPrank();
        
        console.log("[PASS] Battery alert and auto power saving works");
    }
    
    function testDeviceTypeQueries() public {
        // Register different device types
        testSmartphoneRegistration();
        
        // Register a server
        vm.startPrank(serverUser);
        tachyonToken.approve(address(nodeRegistry), 5000 * 10**18);
        
        NodeRegistry.NodeCapabilities memory serverCaps = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.SERVER_TOWER,
            cpuCores: 16,
            cpuFrequencyMHz: 3600,
            ramGB: 128,
            storageGB: 4000,
            gpuMemoryGB: 24,
            gpuModel: "RTX 4090",
            hasGPU: true,
            hasTPU: false,
            bandwidth: 1000,
            uptime: 99,
            isMobile: false,
            batteryCapacityWh: 0,
            operatingSystem: "Ubuntu Server",
            supportsContainers: true,
            supportsKubernetes: true,
            networkLatencyMs: 2,
            isDataCenterHosted: true
        });
        
        bytes memory serverAttestation = abi.encode("server_attestation");
        bytes32 attestationHash = keccak256(abi.encode(serverUser, serverCaps, serverAttestation));
        bytes32 serverHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", attestationHash));
        
        vm.stopPrank();
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorKey, serverHash);
        bytes memory serverSignature = abi.encodePacked(r, s, v);
        
        vm.startPrank(serverUser);
        nodeRegistry.registerNode(serverCaps, serverAttestation, serverSignature);
        vm.stopPrank();
        
        // Test device type queries
        address[] memory smartphones = nodeRegistry.getNodesByDeviceType(
            NodeRegistry.NodeDeviceType.SMARTPHONE
        );
        assertEq(smartphones.length, 1, "Should have 1 smartphone");
        assertEq(smartphones[0], mobileUser, "Should be the mobile user");
        
        address[] memory servers = nodeRegistry.getNodesByDeviceType(
            NodeRegistry.NodeDeviceType.SERVER_TOWER
        );
        assertEq(servers.length, 1, "Should have 1 server");
        assertEq(servers[0], serverUser, "Should be the server user");
        
        console.log("[PASS] Device type queries work correctly");
        console.log("   - Found 1 smartphone");
        console.log("   - Found 1 server");
    }
    
    function testStakeTiers() public {
        // Test that different devices require different stakes
        
        // Mobile devices (low stakes)
        (uint256 smartphoneStake,,,,,,,,,,) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.SMARTPHONE);
        (uint256 tabletStake,,,,,,,,,,) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.TABLET);
        (uint256 rpiStake,,,,,,,,,,) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.RASPBERRY_PI_4);
        
        // Professional devices (high stakes)
        (uint256 workstationStake,,,,,,,,,,) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.WORKSTATION);
        (uint256 gamingStake,,,,,,,,,,) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.GAMING_RIG);
        
        // Enterprise devices (very high stakes)
        (uint256 serverStake,,,,,,,,,,) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.SERVER_RACK_2U);
        (uint256 quantumStake,,,,,,,,,,) = nodeRegistry.deviceProfiles(NodeRegistry.NodeDeviceType.QUANTUM_SIMULATOR);
        
        // Verify stake progression
        assertTrue(smartphoneStake < tabletStake, "Tablet should stake more than smartphone");
        assertTrue(tabletStake < rpiStake, "RPi should stake more than tablet");
        assertTrue(rpiStake < workstationStake, "Workstation should stake more than RPi");
        assertTrue(workstationStake < gamingStake, "Gaming rig should stake more than workstation");
        assertTrue(gamingStake < serverStake, "Server should stake more than gaming rig");
        assertTrue(serverStake < quantumStake, "Quantum should stake most");
        
        console.log("[PASS] Stake tiers properly configured");
        console.log("   - Smartphone: %d TACH", smartphoneStake / 10**18);
        console.log("   - Tablet: %d TACH", tabletStake / 10**18);
        console.log("   - RPi4: %d TACH", rpiStake / 10**18);
        console.log("   - Workstation: %d TACH", workstationStake / 10**18);
        console.log("   - Gaming Rig: %d TACH", gamingStake / 10**18);
        console.log("   - Server 2U: %d TACH", serverStake / 10**18);
        console.log("   - Quantum: %d TACH", quantumStake / 10**18);
    }
    
    function test_RevertWhen_InsufficientStakeForServer() public {
        vm.startPrank(mobileUser);
        
        // Try to register server with insufficient tokens (user only has 1000 TACH, needs 5000)
        tachyonToken.approve(address(nodeRegistry), 1000 * 10**18);
        
        NodeRegistry.NodeCapabilities memory serverCaps = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.SERVER_TOWER,
            cpuCores: 16,
            cpuFrequencyMHz: 3600,
            ramGB: 128,
            storageGB: 4000,
            gpuMemoryGB: 24,
            gpuModel: "RTX 4090",
            hasGPU: true,
            hasTPU: false,
            bandwidth: 1000,
            uptime: 99,
            isMobile: false,
            batteryCapacityWh: 0,
            operatingSystem: "Ubuntu Server",
            supportsContainers: true,
            supportsKubernetes: true,
            networkLatencyMs: 2,
            isDataCenterHosted: true
        });
        
        bytes memory attestationData = abi.encode("server_attestation");
        bytes32 attestationHash = keccak256(abi.encode(mobileUser, serverCaps, attestationData));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", attestationHash));
        
        vm.stopPrank();
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.startPrank(mobileUser);
        
        // This should fail due to insufficient allowance (approved 1000 but needs 5000)
        vm.expectRevert();
        nodeRegistry.registerNode(serverCaps, attestationData, signature);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_NonMobileDeviceWithBattery() public {
        vm.startPrank(serverUser);
        
        tachyonToken.approve(address(nodeRegistry), 5000 * 10**18);
        
        // Try to register server as mobile (should fail validation)
        NodeRegistry.NodeCapabilities memory invalidCaps = NodeRegistry.NodeCapabilities({
            deviceType: NodeRegistry.NodeDeviceType.SERVER_TOWER,
            cpuCores: 16,
            cpuFrequencyMHz: 3200,
            ramGB: 128,
            storageGB: 4000,
            gpuMemoryGB: 8,
            gpuModel: "RTX 3080",
            hasGPU: true,
            hasTPU: false,
            bandwidth: 1000,
            uptime: 99,
            isMobile: true, // This should fail - workstation cannot be mobile
            batteryCapacityWh: 100,
            operatingSystem: "Linux",
            supportsContainers: true,
            supportsKubernetes: true,
            networkLatencyMs: 5,
            isDataCenterHosted: false
        });
        
        bytes memory attestationData = abi.encode("invalid_attestation");
        bytes32 attestationHash = keccak256(abi.encode(serverUser, invalidCaps, attestationData));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", attestationHash));
        
        vm.stopPrank();
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.startPrank(serverUser);
        
        // This should fail validation - servers cannot be mobile
        vm.expectRevert("Server devices cannot be mobile");
        nodeRegistry.registerNode(invalidCaps, attestationData, signature);
        
        vm.stopPrank();
    }
}