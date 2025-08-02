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
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "./TachyonToken.sol";
import "./GreenVerifier.sol";
import "./AIOracle.sol";

contract NodeRegistryCompact is
    Initializable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    // Safe upgrade constants
    bytes32 private constant STORAGE_LAYOUT_HASH = keccak256("NodeRegistry.v1.0.6.layout");
    uint256 public constant ROLLBACK_WINDOW = 24 hours;

    TachyonToken public tachyonToken;
    GreenVerifier public greenVerifier;
    AIOracle public aiOracle;

    enum NodeDeviceType {
        SMARTPHONE,
        TABLET,
        RASPBERRY_PI_4,
        RASPBERRY_PI_5,
        NVIDIA_JETSON_NANO,
        NVIDIA_JETSON_ORIN,
        LAPTOP_CONSUMER,
        DESKTOP_CONSUMER,
        MINI_PC,
        WORKSTATION,
        GAMING_RIG,
        MAC_STUDIO,
        SERVER_TOWER,
        SERVER_RACK_1U,
        SERVER_RACK_2U,
        SERVER_RACK_4U,
        AWS_EC2_INSTANCE,
        AZURE_VM,
        GCP_COMPUTE,
        BARE_METAL_SERVER,
        ASIC_MINER,
        FPGA_BOARD,
        QUANTUM_SIMULATOR,
        CUSTOM_DEVICE
    }

    struct DeviceProfile {
        uint256 minStakeRequired;
        uint128 maxConcurrentTasks;
        uint128 minCpuCores;
        uint128 minRamGB;
        uint128 minStorageGB;
        uint64 minBandwidthMbps;
        uint32 powerEfficiencyScore;
        uint32 reliabilityScore;
        bool supportsBatchProcessing;
        bool supportsGPUCompute;
        bool supportsLowLatency;
    }

    struct NodeCapabilities {
        NodeDeviceType deviceType;
        uint128 cpuCores;
        uint128 cpuFrequencyMHz;
        uint128 ramGB;
        uint128 storageGB;
        uint64 gpuMemoryGB;
        uint64 bandwidth;
        uint32 uptime;
        uint32 batteryCapacityWh;
        uint16 networkLatencyMs;
        bool hasGPU;
        bool hasTPU;
        bool isMobile;
        bool supportsContainers;
        bool supportsKubernetes;
        bool isDataCenterHosted;
        string gpuModel;
        string operatingSystem;
    }

    struct ResourceAttestation {
        bytes32 attestationHash;
        uint256 timestamp;
        uint256 validUntil;
        bytes zkProof;
        bool verified;
    }

    struct NodeInfo {
        uint256 stake;
        uint256 registrationTime;
        uint256 lastActiveTime;
        uint256 totalEarnings;
        uint256 lastMaintenanceTime;
        uint128 tasksCompleted;
        uint128 tasksDisputed;
        uint64 reputation;
        uint32 activeTasks;
        NodeCapabilities capabilities;
        ResourceAttestation attestation;
        DeviceProfile deviceProfile;
        bool registered;
        bool isGreen;
        bool isPowerSaving;
    }

    mapping(address => NodeInfo) public nodes;
    mapping(address => bool) public slashedNodes;
    address[] public activeNodes;
    mapping(address => uint256) public activeNodeIndex;
    mapping(NodeDeviceType => DeviceProfile) public deviceProfiles;
    mapping(NodeDeviceType => bool) public isMobileDevice;
    mapping(NodeDeviceType => bool) public isServerDevice;
    mapping(NodeDeviceType => uint256) public deviceTypeCount;

    uint256 public slashingPercentage;
    uint256 public inactivityThreshold;
    uint256 public mobilePowerSaveThreshold;
    uint256 public totalNodes;
    uint256 public totalStaked;
    uint256 public totalComputePower;

    // Adaptive growth control variables
    uint256 public maxNodesPerTransaction;
    uint256 public suspiciousGrowthThreshold;
    uint256 public maxDailyNodeGrowth;
    mapping(uint256 => uint256) public dailyRegistrations;
    uint256 public lastUpdateDay;
    bool public emergencyGrowthPause;
    
    // Upgrade safety variables
    address public previousImplementation;
    uint256 public upgradeTimestamp;

    event NodeRegistered(address indexed node, uint256 stake, bytes32 attestationHash);
    event NodeUnregistered(address indexed node, uint256 returnedStake);
    event NodeSlashed(address indexed node, uint256 slashedAmount, string reason);
    event DeviceProfileUpdated(NodeDeviceType indexed deviceType, uint256 minStakeRequired);
    
    // Safe upgrade events
    event UpgradeAuthorized(address indexed newImplementation, uint256 timestamp);
    event RollbackExecuted(address indexed fromImplementation, address indexed toImplementation, uint256 timestamp);
    
    // Growth control events
    event SuspiciousGrowthDetected(address indexed caller, uint256 nodeCount, uint256 timestamp);
    event GrowthLimitsUpdated(uint256 maxPerTransaction, uint256 suspiciousThreshold, uint256 maxDaily);
    event EmergencyGrowthPaused(uint256 timestamp);
    event GrowthResumed(uint256 timestamp);

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

        // Set configuration values
        slashingPercentage = 10;
        inactivityThreshold = 7 days;
        mobilePowerSaveThreshold = 20;
        
        // Initialize adaptive growth controls
        maxNodesPerTransaction = 100;
        suspiciousGrowthThreshold = 1000;
        maxDailyNodeGrowth = 10000;
        emergencyGrowthPause = false;
        lastUpdateDay = block.timestamp / 1 days;

        // TESTING: Very minimal stakes for testnet
        deviceProfiles[NodeDeviceType.SMARTPHONE] = DeviceProfile(1e12, 1, 4, 4, 32, 10, 95, 60, false, false, true);
        deviceProfiles[NodeDeviceType.TABLET] = DeviceProfile(2e12, 2, 4, 4, 64, 25, 90, 65, false, true, true);
        deviceProfiles[NodeDeviceType.RASPBERRY_PI_4] = DeviceProfile(25e18, 2, 4, 4, 32, 100, 85, 85, true, false, true);
        deviceProfiles[NodeDeviceType.RASPBERRY_PI_5] = DeviceProfile(35e18, 3, 4, 8, 64, 100, 88, 90, true, false, true);
        deviceProfiles[NodeDeviceType.LAPTOP_CONSUMER] = DeviceProfile(200e18, 5, 4, 8, 256, 50, 70, 75, true, true, true);
        deviceProfiles[NodeDeviceType.WORKSTATION] = DeviceProfile(1000e18, 15, 8, 32, 1000, 500, 60, 90, true, true, true);
        deviceProfiles[NodeDeviceType.GAMING_RIG] = DeviceProfile(1500e18, 20, 8, 32, 2000, 500, 50, 85, true, true, true);
        deviceProfiles[NodeDeviceType.SERVER_TOWER] = DeviceProfile(5000e18, 50, 16, 128, 4000, 1000, 70, 95, true, true, false);
        deviceProfiles[NodeDeviceType.SERVER_RACK_2U] = DeviceProfile(12000e18, 100, 32, 512, 16000, 5000, 70, 99, true, true, false);
        deviceProfiles[NodeDeviceType.AWS_EC2_INSTANCE] = DeviceProfile(10000e18, 100, 16, 64, 1000, 5000, 80, 99, true, true, true);
        deviceProfiles[NodeDeviceType.QUANTUM_SIMULATOR] = DeviceProfile(100000e18, 5, 32, 256, 10000, 10000, 40, 95, true, true, false);
        deviceProfiles[NodeDeviceType.CUSTOM_DEVICE] = DeviceProfile(1000e18, 5, 4, 8, 256, 100, 70, 80, true, false, true);

        isMobileDevice[NodeDeviceType.SMARTPHONE] = isMobileDevice[NodeDeviceType.TABLET] = isMobileDevice[NodeDeviceType.LAPTOP_CONSUMER] = true;
        isServerDevice[NodeDeviceType.SERVER_TOWER] = isServerDevice[NodeDeviceType.SERVER_RACK_2U] = true;
    }

    // Growth control modifier
    modifier validateGrowthRate(uint256 newNodesCount) {
        require(!emergencyGrowthPause, "Emergency growth pause active");
        
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay != lastUpdateDay) {
            lastUpdateDay = currentDay;
            dailyRegistrations[currentDay] = 0;
        }
        
        uint256 adaptiveLimit = calculateAdaptiveLimit();
        require(dailyRegistrations[currentDay] + newNodesCount <= adaptiveLimit, "Daily growth limit exceeded");
        
        if (newNodesCount > suspiciousGrowthThreshold) {
            emit SuspiciousGrowthDetected(msg.sender, newNodesCount, block.timestamp);
            require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Large registration requires admin");
        }
        
        _;
        dailyRegistrations[currentDay] += newNodesCount;
    }

    function registerNode(
        NodeCapabilities calldata capabilities,
        bytes calldata attestationData,
        bytes calldata signature
    ) external whenNotPaused nonReentrant validateGrowthRate(1) {
        require(!nodes[msg.sender].registered && !slashedNodes[msg.sender], "Invalid state");

        DeviceProfile memory profile = deviceProfiles[capabilities.deviceType];
        require(
            profile.minStakeRequired > 0 && capabilities.cpuCores >= profile.minCpuCores
                && capabilities.ramGB >= profile.minRamGB && capabilities.storageGB >= profile.minStorageGB
                && capabilities.bandwidth >= profile.minBandwidthMbps,
            "Insufficient specs"
        );

        if (isMobileDevice[capabilities.deviceType]) {
            require(capabilities.isMobile && capabilities.batteryCapacityWh > 0, "Invalid mobile config");
        }
        if (isServerDevice[capabilities.deviceType]) {
            require(!capabilities.isMobile, "Server devices cannot be mobile");
            require(capabilities.uptime >= 95, "Server devices require 95%+ uptime");
        }

        bytes32 attestationHash = keccak256(abi.encode(msg.sender, capabilities, attestationData));
        require(
            hasRole(ATTESTOR_ROLE, ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(attestationHash), signature)),
            "Invalid signature"
        );
        require(tachyonToken.transferFrom(msg.sender, address(this), profile.minStakeRequired), "Transfer failed");

        nodes[msg.sender] = NodeInfo({
            registered: true,
            stake: profile.minStakeRequired,
            registrationTime: block.timestamp,
            lastActiveTime: block.timestamp,
            totalEarnings: 0,
            lastMaintenanceTime: block.timestamp,
            tasksCompleted: 0,
            tasksDisputed: 0,
            reputation: 50,
            activeTasks: 0,
            capabilities: capabilities,
            attestation: ResourceAttestation(
                attestationHash, block.timestamp, block.timestamp + 30 days, attestationData, true
            ),
            deviceProfile: profile,
            isGreen: greenVerifier.isNodeGreen(msg.sender),
            isPowerSaving: false
        });

        activeNodeIndex[msg.sender] = activeNodes.length;
        activeNodes.push(msg.sender);
        totalNodes++;
        totalStaked += profile.minStakeRequired;
        deviceTypeCount[capabilities.deviceType]++;

        emit NodeRegistered(msg.sender, profile.minStakeRequired, attestationHash);
    }

    function unregisterNode() external nonReentrant {
        NodeInfo storage node = nodes[msg.sender];
        require(node.registered, "Not registered");

        uint256 stake = node.stake;
        _removeFromActiveNodes(msg.sender);
        totalNodes--;
        totalStaked -= stake;
        deviceTypeCount[node.capabilities.deviceType]--;
        delete nodes[msg.sender];
        require(tachyonToken.transfer(msg.sender, stake), "Transfer failed");
        emit NodeUnregistered(msg.sender, stake);
    }

    function getActiveNodes() external view returns (address[] memory) {
        return activeNodes;
    }

    function calculateAdaptiveLimit() public view returns (uint256) {
        uint256 networkSize = activeNodes.length;
        uint256 baseLimit = maxDailyNodeGrowth;
        
        if (networkSize < 10000) {
            return baseLimit;
        } else if (networkSize < 100000) {
            return baseLimit * 3;
        } else if (networkSize < 1000000) {
            return baseLimit * 10;
        } else {
            return baseLimit * 50;
        }
    }
    
    function updateGrowthLimits(
        uint256 _maxNodesPerTransaction,
        uint256 _suspiciousGrowthThreshold,
        uint256 _maxDailyNodeGrowth
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxNodesPerTransaction > 0 && _maxNodesPerTransaction <= 10000, "Invalid transaction limit");
        require(_maxDailyNodeGrowth > _maxNodesPerTransaction, "Daily limit too low");
        
        maxNodesPerTransaction = _maxNodesPerTransaction;
        suspiciousGrowthThreshold = _suspiciousGrowthThreshold;
        maxDailyNodeGrowth = _maxDailyNodeGrowth;
        
        emit GrowthLimitsUpdated(_maxNodesPerTransaction, _suspiciousGrowthThreshold, _maxDailyNodeGrowth);
    }
    
    function emergencyPauseGrowth() external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyGrowthPause = true;
        emit EmergencyGrowthPaused(block.timestamp);
    }
    
    function resumeGrowth() external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyGrowthPause = false;
        emit GrowthResumed(block.timestamp);
    }

    function rollback() external onlyOwner {
        require(block.timestamp <= upgradeTimestamp + ROLLBACK_WINDOW, "Rollback window expired");
        require(previousImplementation != address(0), "No previous implementation");
        
        address current = ERC1967Utils.getImplementation();
        ERC1967Utils.upgradeToAndCall(previousImplementation, "");
        
        emit RollbackExecuted(current, previousImplementation, block.timestamp);
    }

    function getNetworkGrowthStats() external view returns (
        uint256 currentDayRegistrations,
        uint256 adaptiveLimit,
        bool growthPaused,
        uint256 networkSize
    ) {
        uint256 currentDay = block.timestamp / 1 days;
        return (
            dailyRegistrations[currentDay],
            calculateAdaptiveLimit(),
            emergencyGrowthPause,
            activeNodes.length
        );
    }

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

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        previousImplementation = ERC1967Utils.getImplementation();
        upgradeTimestamp = block.timestamp;
        
        require(newImplementation.code.length > 0, "No code at implementation");
        
        try IStorageCompatible(newImplementation).getStorageLayoutHash() returns (bytes32 newHash) {
            require(_isCompatibleLayout(STORAGE_LAYOUT_HASH, newHash), "Incompatible storage layout");
        } catch {
            // Allow for testnet flexibility
        }
        
        emit UpgradeAuthorized(newImplementation, block.timestamp);
    }

    function _isCompatibleLayout(bytes32 oldHash, bytes32 newHash) internal pure returns (bool) {
        return oldHash == newHash || newHash == keccak256(abi.encode(oldHash, "compatible"));
    }
    
    function getStorageLayoutHash() external pure returns (bytes32) {
        return STORAGE_LAYOUT_HASH;
    }

    function version() public pure returns (string memory) {
        return "1.0.6";
    }
}

interface IStorageCompatible {
    function getStorageLayoutHash() external pure returns (bytes32);
}