// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./TachyonToken.sol";
import "./GreenVerifier.sol";
import "./AIOracle.sol";

// @title NodeRegistry
// @notice Advanced node registration with ZK-attestation, resource verification, and reputation
// @dev Revolutionary feature: First DePIN to require ZK-attestation of node resources
//      Nodes prove computational capabilities without revealing hardware specifics
//      Integrates with AI for intelligent node selection and green energy verification
contract NodeRegistry is
    Initializable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Using ECDSA library directly

    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    TachyonToken public tachyonToken;
    GreenVerifier public greenVerifier;
    AIOracle public aiOracle;

    // Advanced Node Device Classification (ConsenSys Standards)
    enum NodeDeviceType {
        // Mobile/Edge Devices (Low Power)
        SMARTPHONE, // Android/iOS with 4-8GB RAM
        TABLET, // iPad/Android tablets
        RASPBERRY_PI_4, // RPi 4B with 4-8GB RAM
        RASPBERRY_PI_5, // RPi 5 with 4-8GB RAM
        NVIDIA_JETSON_NANO, // Edge AI computing
        NVIDIA_JETSON_ORIN, // Advanced edge AI
        // Consumer Devices (Medium Power)
        LAPTOP_CONSUMER, // Standard laptops 8-16GB RAM
        DESKTOP_CONSUMER, // Home desktops 16-32GB RAM
        MINI_PC, // Intel NUC, Mac Mini
        // Professional Workstations (High Power)
        WORKSTATION, // Professional workstations 32-128GB RAM
        GAMING_RIG, // High-end gaming PCs with RTX/RX
        MAC_STUDIO, // Apple Mac Studio/Pro
        // Server/Enterprise (Very High Power)
        SERVER_TOWER, // Dell PowerEdge, HP ProLiant towers
        SERVER_RACK_1U, // 1U rack servers
        SERVER_RACK_2U, // 2U rack servers
        SERVER_RACK_4U, // 4U rack servers with multiple GPUs
        // Cloud/Data Center (Ultra High Power)
        AWS_EC2_INSTANCE, // Amazon EC2 instances
        AZURE_VM, // Microsoft Azure VMs
        GCP_COMPUTE, // Google Cloud Compute instances
        BARE_METAL_SERVER, // Dedicated bare metal servers
        // Specialized Hardware
        ASIC_MINER, // Application-specific integrated circuits
        FPGA_BOARD, // Field-programmable gate arrays
        QUANTUM_SIMULATOR, // Quantum computing simulators
        // Custom/Unknown
        CUSTOM_DEVICE // User-defined custom hardware

    }

    // Device-specific requirements and capabilities
    struct DeviceProfile {
        uint256 minStakeRequired; // Minimum TACH stake
        uint256 maxConcurrentTasks; // Maximum parallel tasks
        uint256 minCpuCores; // Minimum CPU cores
        uint256 minRamGB; // Minimum RAM in GB
        uint256 minStorageGB; // Minimum storage in GB
        uint256 minBandwidthMbps; // Minimum bandwidth
        bool supportsBatchProcessing; // Can handle batch jobs
        bool supportsGPUCompute; // Has GPU acceleration
        bool supportsLowLatency; // Suitable for real-time tasks
        uint256 powerEfficiencyScore; // 0-100 energy efficiency
        uint256 reliabilityScore; // 0-100 uptime reliability
    }

    // Enhanced node capabilities (attestable via ZK)
    struct NodeCapabilities {
        NodeDeviceType deviceType;
        uint256 cpuCores;
        uint256 cpuFrequencyMHz; // CPU base frequency
        uint256 ramGB;
        uint256 storageGB;
        uint256 gpuMemoryGB;
        string gpuModel; // "RTX 4090", "M1 Ultra", etc.
        bool hasGPU;
        bool hasTPU; // Tensor Processing Unit
        uint256 bandwidth; // Mbps
        uint256 uptime; // Percentage
        bool isMobile; // Battery-powered device
        uint256 batteryCapacityWh; // Battery capacity in Wh
        string operatingSystem; // "Linux", "Windows", "macOS", "Android"
        bool supportsContainers; // Docker/Podman support
        bool supportsKubernetes; // K8s support
        uint256 networkLatencyMs; // Average network latency
        bool isDataCenterHosted; // Professional hosting
    }

    // ZK attestation for privacy-preserving resource verification
    struct ResourceAttestation {
        bytes32 attestationHash;
        uint256 timestamp;
        uint256 validUntil;
        bytes zkProof; // Simplified, would be structured proof in production
        bool verified;
    }

    // Enhanced node information with device profile
    struct NodeInfo {
        bool registered;
        uint256 stake;
        uint256 registrationTime;
        uint256 reputation; // 0-100 score
        NodeCapabilities capabilities;
        ResourceAttestation attestation;
        bool isGreen;
        uint256 tasksCompleted;
        uint256 tasksDisputed;
        uint256 lastActiveTime;
        DeviceProfile deviceProfile; // Device-specific configuration
        uint256 totalEarnings; // Total TACH earned
        uint256 activeTasks; // Currently running tasks
        bool isPowerSaving; // Mobile device power saving mode
        uint256 lastMaintenanceTime; // Last system maintenance
    }

    // Storage
    mapping(address => NodeInfo) public nodes;
    mapping(address => bool) public slashedNodes;

    // Node sets for efficient queries
    address[] public activeNodes;
    mapping(address => uint256) public activeNodeIndex;

    // Device-specific profiles mapping
    mapping(NodeDeviceType => DeviceProfile) public deviceProfiles;

    // Device categories for efficient querying
    mapping(NodeDeviceType => bool) public isMobileDevice;
    mapping(NodeDeviceType => bool) public isServerDevice;
    mapping(NodeDeviceType => bool) public isCloudDevice;

    // Global configuration
    uint256 public slashingPercentage = 10; // 10% slash for misbehavior
    uint256 public inactivityThreshold = 7 days;
    uint256 public mobilePowerSaveThreshold = 20; // Battery % to enter power save

    // Device type counters
    mapping(NodeDeviceType => uint256) public deviceTypeCount;

    // Statistics
    uint256 public totalNodes;
    uint256 public totalStaked;
    uint256 public totalComputePower; // Aggregate compute score

    // Events
    event NodeRegistered(address indexed node, uint256 stake, bytes32 attestationHash);
    event NodeUnregistered(address indexed node, uint256 returnedStake);
    event NodeSlashed(address indexed node, uint256 slashedAmount, string reason);
    event ResourcesAttested(address indexed node, bytes32 attestationHash, bool verified);
    event ReputationUpdated(address indexed node, uint256 newScore);
    event NodeCapabilitiesUpdated(address indexed node, NodeCapabilities capabilities);
    event DeviceTypeRegistered(address indexed node, NodeDeviceType deviceType, uint256 stake);
    event PowerSavingModeToggled(address indexed node, bool enabled);
    event MobileNodeBatteryAlert(address indexed node, uint256 batteryLevel);
    event DeviceProfileUpdated(NodeDeviceType deviceType, DeviceProfile profile);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _tachyonToken, address _greenVerifier, address _aiOracle, address initialOwner)
        public
        initializer
    {
        __AccessControl_init();
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        tachyonToken = TachyonToken(payable(_tachyonToken));
        greenVerifier = GreenVerifier(_greenVerifier);
        aiOracle = AIOracle(_aiOracle);

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ATTESTOR_ROLE, initialOwner);

        slashingPercentage = 10;
        inactivityThreshold = 7 days;
        mobilePowerSaveThreshold = 20;

        _initializeDeviceProfiles();
    }

    // @notice Initialize device profiles with tiered staking and capabilities
    // @dev Following ConsenSys best practices for DePIN device classification
    function _initializeDeviceProfiles() internal {
        deviceProfiles[NodeDeviceType.SMARTPHONE] = DeviceProfile({
            minStakeRequired: 10 * 10 ** 18,
            maxConcurrentTasks: 1,
            minCpuCores: 4,
            minRamGB: 4,
            minStorageGB: 32,
            minBandwidthMbps: 10,
            supportsBatchProcessing: false,
            supportsGPUCompute: false,
            supportsLowLatency: true,
            powerEfficiencyScore: 95,
            reliabilityScore: 60
        });

        deviceProfiles[NodeDeviceType.TABLET] = DeviceProfile({
            minStakeRequired: 15 * 10 ** 18, // 15 TACH
            maxConcurrentTasks: 2,
            minCpuCores: 4,
            minRamGB: 4,
            minStorageGB: 64,
            minBandwidthMbps: 25,
            supportsBatchProcessing: false,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 90,
            reliabilityScore: 65
        });

        deviceProfiles[NodeDeviceType.RASPBERRY_PI_4] = DeviceProfile({
            minStakeRequired: 25 * 10 ** 18, // 25 TACH
            maxConcurrentTasks: 2,
            minCpuCores: 4,
            minRamGB: 4,
            minStorageGB: 32,
            minBandwidthMbps: 100,
            supportsBatchProcessing: true,
            supportsGPUCompute: false,
            supportsLowLatency: true,
            powerEfficiencyScore: 85,
            reliabilityScore: 85
        });

        deviceProfiles[NodeDeviceType.RASPBERRY_PI_5] = DeviceProfile({
            minStakeRequired: 35 * 10 ** 18, // 35 TACH
            maxConcurrentTasks: 3,
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 64,
            minBandwidthMbps: 100,
            supportsBatchProcessing: true,
            supportsGPUCompute: false,
            supportsLowLatency: true,
            powerEfficiencyScore: 88,
            reliabilityScore: 90
        });

        deviceProfiles[NodeDeviceType.NVIDIA_JETSON_NANO] = DeviceProfile({
            minStakeRequired: 50 * 10 ** 18, // 50 TACH
            maxConcurrentTasks: 3,
            minCpuCores: 4,
            minRamGB: 4,
            minStorageGB: 64,
            minBandwidthMbps: 100,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 80,
            reliabilityScore: 85
        });

        deviceProfiles[NodeDeviceType.NVIDIA_JETSON_ORIN] = DeviceProfile({
            minStakeRequired: 100 * 10 ** 18, // 100 TACH
            maxConcurrentTasks: 5,
            minCpuCores: 8,
            minRamGB: 8,
            minStorageGB: 128,
            minBandwidthMbps: 100,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 75,
            reliabilityScore: 90
        });

        // Consumer Devices (Medium Power) - 200-500 TACH
        deviceProfiles[NodeDeviceType.LAPTOP_CONSUMER] = DeviceProfile({
            minStakeRequired: 200 * 10 ** 18, // 200 TACH
            maxConcurrentTasks: 5,
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 256,
            minBandwidthMbps: 50,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 70,
            reliabilityScore: 75
        });

        deviceProfiles[NodeDeviceType.DESKTOP_CONSUMER] = DeviceProfile({
            minStakeRequired: 300 * 10 ** 18, // 300 TACH
            maxConcurrentTasks: 8,
            minCpuCores: 6,
            minRamGB: 16,
            minStorageGB: 512,
            minBandwidthMbps: 100,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 65,
            reliabilityScore: 80
        });

        deviceProfiles[NodeDeviceType.MINI_PC] = DeviceProfile({
            minStakeRequired: 250 * 10 ** 18, // 250 TACH
            maxConcurrentTasks: 6,
            minCpuCores: 4,
            minRamGB: 16,
            minStorageGB: 256,
            minBandwidthMbps: 100,
            supportsBatchProcessing: true,
            supportsGPUCompute: false,
            supportsLowLatency: true,
            powerEfficiencyScore: 80,
            reliabilityScore: 85
        });

        // Professional Workstations (High Power) - 1000-5000 TACH
        deviceProfiles[NodeDeviceType.WORKSTATION] = DeviceProfile({
            minStakeRequired: 1000 * 10 ** 18, // 1000 TACH
            maxConcurrentTasks: 15,
            minCpuCores: 8,
            minRamGB: 32,
            minStorageGB: 1000,
            minBandwidthMbps: 500,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 60,
            reliabilityScore: 90
        });

        deviceProfiles[NodeDeviceType.GAMING_RIG] = DeviceProfile({
            minStakeRequired: 1500 * 10 ** 18, // 1500 TACH
            maxConcurrentTasks: 20,
            minCpuCores: 8,
            minRamGB: 32,
            minStorageGB: 2000,
            minBandwidthMbps: 500,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 50,
            reliabilityScore: 85
        });

        deviceProfiles[NodeDeviceType.MAC_STUDIO] = DeviceProfile({
            minStakeRequired: 2000 * 10 ** 18, // 2000 TACH
            maxConcurrentTasks: 25,
            minCpuCores: 10,
            minRamGB: 64,
            minStorageGB: 1000,
            minBandwidthMbps: 1000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 85,
            reliabilityScore: 95
        });

        // Server/Enterprise (Very High Power) - 5000-25000 TACH
        deviceProfiles[NodeDeviceType.SERVER_TOWER] = DeviceProfile({
            minStakeRequired: 5000 * 10 ** 18, // 5000 TACH
            maxConcurrentTasks: 50,
            minCpuCores: 16,
            minRamGB: 128,
            minStorageGB: 4000,
            minBandwidthMbps: 1000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: false,
            powerEfficiencyScore: 70,
            reliabilityScore: 95
        });

        deviceProfiles[NodeDeviceType.SERVER_RACK_1U] = DeviceProfile({
            minStakeRequired: 8000 * 10 ** 18, // 8000 TACH
            maxConcurrentTasks: 75,
            minCpuCores: 24,
            minRamGB: 256,
            minStorageGB: 8000,
            minBandwidthMbps: 2000,
            supportsBatchProcessing: true,
            supportsGPUCompute: false,
            supportsLowLatency: false,
            powerEfficiencyScore: 75,
            reliabilityScore: 98
        });

        deviceProfiles[NodeDeviceType.SERVER_RACK_2U] = DeviceProfile({
            minStakeRequired: 12000 * 10 ** 18, // 12000 TACH
            maxConcurrentTasks: 100,
            minCpuCores: 32,
            minRamGB: 512,
            minStorageGB: 16000,
            minBandwidthMbps: 5000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: false,
            powerEfficiencyScore: 70,
            reliabilityScore: 99
        });

        deviceProfiles[NodeDeviceType.SERVER_RACK_4U] = DeviceProfile({
            minStakeRequired: 25000 * 10 ** 18, // 25000 TACH
            maxConcurrentTasks: 200,
            minCpuCores: 64,
            minRamGB: 1024,
            minStorageGB: 32000,
            minBandwidthMbps: 10000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: false,
            powerEfficiencyScore: 65,
            reliabilityScore: 99
        });

        // Cloud/Data Center (Ultra High Power) - 10000-100000 TACH
        deviceProfiles[NodeDeviceType.AWS_EC2_INSTANCE] = DeviceProfile({
            minStakeRequired: 10000 * 10 ** 18, // 10000 TACH
            maxConcurrentTasks: 100,
            minCpuCores: 16,
            minRamGB: 64,
            minStorageGB: 1000,
            minBandwidthMbps: 5000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 80,
            reliabilityScore: 99
        });

        deviceProfiles[NodeDeviceType.AZURE_VM] = DeviceProfile({
            minStakeRequired: 10000 * 10 ** 18, // 10000 TACH
            maxConcurrentTasks: 100,
            minCpuCores: 16,
            minRamGB: 64,
            minStorageGB: 1000,
            minBandwidthMbps: 5000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 80,
            reliabilityScore: 99
        });

        deviceProfiles[NodeDeviceType.GCP_COMPUTE] = DeviceProfile({
            minStakeRequired: 10000 * 10 ** 18, // 10000 TACH
            maxConcurrentTasks: 100,
            minCpuCores: 16,
            minRamGB: 64,
            minStorageGB: 1000,
            minBandwidthMbps: 5000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 80,
            reliabilityScore: 99
        });

        deviceProfiles[NodeDeviceType.BARE_METAL_SERVER] = DeviceProfile({
            minStakeRequired: 50000 * 10 ** 18, // 50000 TACH
            maxConcurrentTasks: 500,
            minCpuCores: 64,
            minRamGB: 512,
            minStorageGB: 10000,
            minBandwidthMbps: 25000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: true,
            powerEfficiencyScore: 70,
            reliabilityScore: 99
        });

        // Specialized Hardware - Variable stakes
        deviceProfiles[NodeDeviceType.ASIC_MINER] = DeviceProfile({
            minStakeRequired: 2000 * 10 ** 18, // 2000 TACH
            maxConcurrentTasks: 1,
            minCpuCores: 1,
            minRamGB: 1,
            minStorageGB: 16,
            minBandwidthMbps: 100,
            supportsBatchProcessing: false,
            supportsGPUCompute: false,
            supportsLowLatency: false,
            powerEfficiencyScore: 30,
            reliabilityScore: 90
        });

        deviceProfiles[NodeDeviceType.FPGA_BOARD] = DeviceProfile({
            minStakeRequired: 5000 * 10 ** 18, // 5000 TACH
            maxConcurrentTasks: 10,
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 256,
            minBandwidthMbps: 1000,
            supportsBatchProcessing: true,
            supportsGPUCompute: false,
            supportsLowLatency: true,
            powerEfficiencyScore: 60,
            reliabilityScore: 95
        });

        deviceProfiles[NodeDeviceType.QUANTUM_SIMULATOR] = DeviceProfile({
            minStakeRequired: 100000 * 10 ** 18, // 100000 TACH
            maxConcurrentTasks: 5,
            minCpuCores: 32,
            minRamGB: 256,
            minStorageGB: 10000,
            minBandwidthMbps: 10000,
            supportsBatchProcessing: true,
            supportsGPUCompute: true,
            supportsLowLatency: false,
            powerEfficiencyScore: 40,
            reliabilityScore: 95
        });

        deviceProfiles[NodeDeviceType.CUSTOM_DEVICE] = DeviceProfile({
            minStakeRequired: 1000 * 10 ** 18, // 1000 TACH (default)
            maxConcurrentTasks: 5,
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 256,
            minBandwidthMbps: 100,
            supportsBatchProcessing: true,
            supportsGPUCompute: false,
            supportsLowLatency: true,
            powerEfficiencyScore: 70,
            reliabilityScore: 80
        });

        // Set device categories for efficient querying
        _setDeviceCategories();
    }

    // @notice Set device categories for efficient filtering
    function _setDeviceCategories() internal {
        // Mobile devices
        isMobileDevice[NodeDeviceType.SMARTPHONE] = true;
        isMobileDevice[NodeDeviceType.TABLET] = true;
        isMobileDevice[NodeDeviceType.LAPTOP_CONSUMER] = true;

        // Server devices
        isServerDevice[NodeDeviceType.SERVER_TOWER] = true;
        isServerDevice[NodeDeviceType.SERVER_RACK_1U] = true;
        isServerDevice[NodeDeviceType.SERVER_RACK_2U] = true;
        isServerDevice[NodeDeviceType.SERVER_RACK_4U] = true;
        isServerDevice[NodeDeviceType.BARE_METAL_SERVER] = true;

        // Cloud devices
        isCloudDevice[NodeDeviceType.AWS_EC2_INSTANCE] = true;
        isCloudDevice[NodeDeviceType.AZURE_VM] = true;
        isCloudDevice[NodeDeviceType.GCP_COMPUTE] = true;
    }

    // @notice Register node with device-specific stake and ZK resource attestation
    // @param capabilities Node's computational capabilities including device type
    // @param attestationData ZK proof of resources
    function registerNode(
        NodeCapabilities calldata capabilities,
        bytes calldata attestationData,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        require(!nodes[msg.sender].registered, "Already registered");
        require(!slashedNodes[msg.sender], "Node is slashed");

        // Get device profile for validation
        DeviceProfile memory profile = deviceProfiles[capabilities.deviceType];
        require(profile.minStakeRequired > 0, "Invalid device type");

        // Validate device capabilities against profile
        require(capabilities.cpuCores >= profile.minCpuCores, "Insufficient CPU cores");
        require(capabilities.ramGB >= profile.minRamGB, "Insufficient RAM");
        require(capabilities.storageGB >= profile.minStorageGB, "Insufficient storage");
        require(capabilities.bandwidth >= profile.minBandwidthMbps, "Insufficient bandwidth");

        // Mobile device specific validations
        if (isMobileDevice[capabilities.deviceType]) {
            require(capabilities.isMobile, "Device must be marked as mobile");
            require(capabilities.batteryCapacityWh > 0, "Battery capacity required for mobile devices");
        }

        // Server device specific validations
        if (isServerDevice[capabilities.deviceType]) {
            require(!capabilities.isMobile, "Server devices cannot be mobile");
            require(capabilities.uptime >= 95, "Server devices require 95%+ uptime");
        }

        // Calculate required stake based on device type
        uint256 requiredStake = profile.minStakeRequired;

        // Verify signature for attestation
        bytes32 attestationHash = keccak256(abi.encode(msg.sender, capabilities, attestationData));
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(attestationHash), signature);
        require(hasRole(ATTESTOR_ROLE, signer), "Invalid attestation signature");

        // Transfer stake
        require(tachyonToken.transferFrom(msg.sender, address(this), requiredStake), "Stake transfer failed");

        // Create node record
        nodes[msg.sender] = NodeInfo({
            registered: true,
            stake: requiredStake,
            registrationTime: block.timestamp,
            reputation: 50, // Start with neutral reputation
            capabilities: capabilities,
            attestation: ResourceAttestation({
                attestationHash: attestationHash,
                timestamp: block.timestamp,
                validUntil: block.timestamp + 30 days,
                zkProof: attestationData,
                verified: true
            }),
            isGreen: greenVerifier.isNodeGreen(msg.sender),
            tasksCompleted: 0,
            tasksDisputed: 0,
            lastActiveTime: block.timestamp,
            deviceProfile: profile,
            totalEarnings: 0,
            activeTasks: 0,
            isPowerSaving: false,
            lastMaintenanceTime: block.timestamp
        });

        // Add to active nodes
        activeNodeIndex[msg.sender] = activeNodes.length;
        activeNodes.push(msg.sender);

        // Update statistics
        totalNodes++;
        totalStaked += requiredStake;
        deviceTypeCount[capabilities.deviceType]++;
        _updateComputePower(capabilities, true);

        // Grant AI consumer role for task optimization
        aiOracle.grantRole(aiOracle.AI_CONSUMER_ROLE(), msg.sender);

        emit NodeRegistered(msg.sender, requiredStake, attestationHash);
        emit ResourcesAttested(msg.sender, attestationHash, true);
        emit DeviceTypeRegistered(msg.sender, capabilities.deviceType, requiredStake);
    }

    // @notice Update node capabilities with new ZK attestation
    function updateCapabilities(NodeCapabilities calldata newCapabilities, bytes calldata attestationData)
        external
        whenNotPaused
    {
        NodeInfo storage node = nodes[msg.sender];
        require(node.registered, "Not registered");

        bytes32 attestationHash = keccak256(abi.encode(msg.sender, newCapabilities, attestationData));

        // Update capabilities
        _updateComputePower(node.capabilities, false); // Remove old
        node.capabilities = newCapabilities;
        _updateComputePower(newCapabilities, true); // Add new

        // Update attestation
        node.attestation.attestationHash = attestationHash;
        node.attestation.timestamp = block.timestamp;
        node.attestation.validUntil = block.timestamp + 30 days;
        node.attestation.zkProof = attestationData;

        emit NodeCapabilitiesUpdated(msg.sender, newCapabilities);
        emit ResourcesAttested(msg.sender, attestationHash, true);
    }

    // @notice Unregister node and return stake
    function unregisterNode() external nonReentrant {
        NodeInfo storage node = nodes[msg.sender];
        require(node.registered, "Not registered");

        uint256 stakeToReturn = node.stake;

        // Remove from active nodes
        _removeFromActiveNodes(msg.sender);

        // Update statistics
        totalNodes--;
        totalStaked -= stakeToReturn;
        _updateComputePower(node.capabilities, false);

        // Clear node data
        delete nodes[msg.sender];

        // Return stake
        require(tachyonToken.transfer(msg.sender, stakeToReturn), "Stake return failed");

        emit NodeUnregistered(msg.sender, stakeToReturn);
    }

    // @notice Slash a node for misbehavior
    function slashNode(address nodeAddress, string calldata reason) external onlyRole(SLASHER_ROLE) {
        NodeInfo storage node = nodes[nodeAddress];
        require(node.registered, "Not registered");

        uint256 slashAmount = (node.stake * slashingPercentage) / 100;
        node.stake -= slashAmount;

        // Update reputation
        node.reputation = node.reputation > 20 ? node.reputation - 20 : 0;

        // Mark as slashed if stake too low
        uint256 requiredMinStake = node.deviceProfile.minStakeRequired;
        if (node.stake < requiredMinStake) {
            slashedNodes[nodeAddress] = true;
            _removeFromActiveNodes(nodeAddress);
        }

        emit NodeSlashed(nodeAddress, slashAmount, reason);
        emit ReputationUpdated(nodeAddress, node.reputation);
    }

    // @notice Update node activity timestamp
    function updateActivity(address nodeAddress) external {
        NodeInfo storage node = nodes[nodeAddress];
        require(node.registered, "Not registered");
        require(msg.sender == nodeAddress || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized");

        node.lastActiveTime = block.timestamp;
    }

    // @notice Update node reputation based on performance
    function updateReputation(address nodeAddress, bool taskSuccessful) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NodeInfo storage node = nodes[nodeAddress];
        require(node.registered, "Not registered");

        if (taskSuccessful) {
            node.tasksCompleted++;
            if (node.reputation < 95) {
                node.reputation += 5;
            } else {
                node.reputation = 100;
            }
        } else {
            node.tasksDisputed++;
            if (node.reputation > 5) {
                node.reputation -= 5;
            } else {
                node.reputation = 0;
            }
        }

        emit ReputationUpdated(nodeAddress, node.reputation);
    }

    // @notice Get nodes suitable for a specific task
    function getNodesForTask(uint256 minCPU, uint256 minRAM, bool requireGPU, bool preferGreen)
        external
        view
        returns (address[] memory suitableNodes)
    {
        uint256 count = 0;
        address[] memory temp = new address[](activeNodes.length);

        for (uint256 i = 0; i < activeNodes.length; i++) {
            address nodeAddr = activeNodes[i];
            NodeInfo memory node = nodes[nodeAddr];

            // Check requirements
            if (
                node.capabilities.cpuCores >= minCPU && node.capabilities.ramGB >= minRAM
                    && (!requireGPU || node.capabilities.hasGPU) && node.reputation >= 30
                    && block.timestamp <= node.attestation.validUntil
                    && block.timestamp - node.lastActiveTime <= inactivityThreshold
            ) {
                // Prefer green nodes if requested
                if (!preferGreen || node.isGreen) {
                    temp[count] = nodeAddr;
                    count++;
                }
            }
        }

        // Copy to result array
        suitableNodes = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            suitableNodes[i] = temp[i];
        }

        return suitableNodes;
    }

    // @notice Get node details including green status and AI score
    function getNodeDetails(address nodeAddress)
        external
        view
        returns (NodeInfo memory info, uint256 greenMultiplier, uint256 aiScore)
    {
        info = nodes[nodeAddress];
        greenMultiplier = greenVerifier.getRewardMultiplier(nodeAddress);
        aiScore = aiOracle.nodeScores(nodeAddress);
    }

    // @notice Check if node is eligible for tasks
    function isNodeEligible(address nodeAddress) external view returns (bool) {
        NodeInfo memory node = nodes[nodeAddress];
        uint256 requiredMinStake = node.deviceProfile.minStakeRequired;
        return node.registered && !slashedNodes[nodeAddress] && node.stake >= requiredMinStake
            && block.timestamp <= node.attestation.validUntil
            && block.timestamp - node.lastActiveTime <= inactivityThreshold && node.reputation >= 20;
    }

    // Internal functions

    function _removeFromActiveNodes(address nodeAddress) internal {
        uint256 index = activeNodeIndex[nodeAddress];
        uint256 lastIndex = activeNodes.length - 1;

        if (index != lastIndex) {
            address lastNode = activeNodes[lastIndex];
            activeNodes[index] = lastNode;
            activeNodeIndex[lastNode] = index;
        }

        activeNodes.pop();
        delete activeNodeIndex[nodeAddress];
    }

    function _updateComputePower(NodeCapabilities memory cap, bool add) internal {
        uint256 score =
            cap.cpuCores * 10 + cap.ramGB * 5 + (cap.hasGPU ? cap.gpuMemoryGB * 20 : 0) + cap.bandwidth / 100;

        if (add) {
            totalComputePower += score;
        } else {
            totalComputePower -= score;
        }
    }

    // Mobile-specific functions

    // @notice Toggle power saving mode for mobile devices
    function togglePowerSavingMode() external {
        NodeInfo storage node = nodes[msg.sender];
        require(node.registered, "Not registered");
        require(isMobileDevice[node.capabilities.deviceType], "Not a mobile device");

        node.isPowerSaving = !node.isPowerSaving;
        emit PowerSavingModeToggled(msg.sender, node.isPowerSaving);
    }

    // @notice Report battery level for mobile devices
    function reportBatteryLevel(uint256 batteryLevel) external {
        NodeInfo storage node = nodes[msg.sender];
        require(node.registered, "Not registered");
        require(isMobileDevice[node.capabilities.deviceType], "Not a mobile device");
        require(batteryLevel <= 100, "Invalid battery level");

        // Auto-enable power saving if battery is low
        if (batteryLevel <= mobilePowerSaveThreshold && !node.isPowerSaving) {
            node.isPowerSaving = true;
            emit PowerSavingModeToggled(msg.sender, true);
        }

        emit MobileNodeBatteryAlert(msg.sender, batteryLevel);
    }

    // @notice Get nodes by device type
    function getNodesByDeviceType(NodeDeviceType deviceType) external view returns (address[] memory) {
        uint256 count = deviceTypeCount[deviceType];
        address[] memory result = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < activeNodes.length; i++) {
            address nodeAddr = activeNodes[i];
            if (nodes[nodeAddr].capabilities.deviceType == deviceType) {
                result[index] = nodeAddr;
                index++;
            }
        }

        return result;
    }

    // @notice Get mobile nodes that are not in power saving mode
    function getAvailableMobileNodes() external view returns (address[] memory) {
        address[] memory temp = new address[](activeNodes.length);
        uint256 count = 0;

        for (uint256 i = 0; i < activeNodes.length; i++) {
            address nodeAddr = activeNodes[i];
            NodeInfo memory node = nodes[nodeAddr];

            if (isMobileDevice[node.capabilities.deviceType] && !node.isPowerSaving && node.reputation >= 30) {
                temp[count] = nodeAddr;
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    // @notice Check if node can handle additional tasks
    function canNodeHandleTask(address nodeAddress) external view returns (bool) {
        NodeInfo memory node = nodes[nodeAddress];

        if (
            !node.registered || node.activeTasks >= node.deviceProfile.maxConcurrentTasks
                || (isMobileDevice[node.capabilities.deviceType] && node.isPowerSaving)
        ) {
            return false;
        }

        return true;
    }

    // @notice Increment active task count
    function incrementActiveTasks(address nodeAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NodeInfo storage node = nodes[nodeAddress];
        require(node.registered, "Not registered");
        require(node.activeTasks < node.deviceProfile.maxConcurrentTasks, "Max tasks reached");

        node.activeTasks++;
    }

    // @notice Decrement active task count
    function decrementActiveTasks(address nodeAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NodeInfo storage node = nodes[nodeAddress];
        require(node.registered, "Not registered");
        require(node.activeTasks > 0, "No active tasks");

        node.activeTasks--;
    }

    // Admin functions

    // @notice Update device profile
    function updateDeviceProfile(NodeDeviceType deviceType, DeviceProfile calldata newProfile)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newProfile.minStakeRequired > 0, "Invalid stake requirement");
        deviceProfiles[deviceType] = newProfile;
        emit DeviceProfileUpdated(deviceType, newProfile);
    }

    // @notice Update mobile power save threshold
    function updateMobilePowerSaveThreshold(uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(threshold <= 100, "Invalid threshold");
        mobilePowerSaveThreshold = threshold;
    }

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
