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

contract NodeRegistry is
    Initializable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

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

    event NodeRegistered(address indexed node, uint256 stake, bytes32 attestationHash);
    event NodeUnregistered(address indexed node, uint256 returnedStake);
    event NodeSlashed(address indexed node, uint256 slashedAmount, string reason);

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

        // Compact device profile initialization - all required devices
        deviceProfiles[NodeDeviceType.SMARTPHONE] = DeviceProfile(10e18, 1, 4, 4, 32, 10, 95, 60, false, false, true);
        deviceProfiles[NodeDeviceType.TABLET] = DeviceProfile(15e18, 2, 4, 4, 64, 25, 90, 65, false, true, true);
        deviceProfiles[NodeDeviceType.RASPBERRY_PI_4] =
            DeviceProfile(25e18, 2, 4, 4, 32, 100, 85, 85, true, false, true);
        deviceProfiles[NodeDeviceType.RASPBERRY_PI_5] =
            DeviceProfile(35e18, 3, 4, 8, 64, 100, 88, 90, true, false, true);
        deviceProfiles[NodeDeviceType.LAPTOP_CONSUMER] =
            DeviceProfile(200e18, 5, 4, 8, 256, 50, 70, 75, true, true, true);
        deviceProfiles[NodeDeviceType.WORKSTATION] =
            DeviceProfile(1000e18, 15, 8, 32, 1000, 500, 60, 90, true, true, true);
        deviceProfiles[NodeDeviceType.GAMING_RIG] =
            DeviceProfile(1500e18, 20, 8, 32, 2000, 500, 50, 85, true, true, true);
        deviceProfiles[NodeDeviceType.SERVER_TOWER] =
            DeviceProfile(5000e18, 50, 16, 128, 4000, 1000, 70, 95, true, true, false);
        deviceProfiles[NodeDeviceType.SERVER_RACK_2U] =
            DeviceProfile(12000e18, 100, 32, 512, 16000, 5000, 70, 99, true, true, false);
        deviceProfiles[NodeDeviceType.AWS_EC2_INSTANCE] =
            DeviceProfile(10000e18, 100, 16, 64, 1000, 5000, 80, 99, true, true, true);
        deviceProfiles[NodeDeviceType.QUANTUM_SIMULATOR] =
            DeviceProfile(100000e18, 5, 32, 256, 10000, 10000, 40, 95, true, true, false);
        deviceProfiles[NodeDeviceType.CUSTOM_DEVICE] =
            DeviceProfile(1000e18, 5, 4, 8, 256, 100, 70, 80, true, false, true);

        isMobileDevice[NodeDeviceType.SMARTPHONE] =
            isMobileDevice[NodeDeviceType.TABLET] = isMobileDevice[NodeDeviceType.LAPTOP_CONSUMER] = true;
        isServerDevice[NodeDeviceType.SERVER_TOWER] = isServerDevice[NodeDeviceType.SERVER_RACK_2U] = true;
    }

    function registerNode(
        NodeCapabilities calldata capabilities,
        bytes calldata attestationData,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
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

    function slashNode(address nodeAddress, string calldata reason) external onlyRole(SLASHER_ROLE) {
        NodeInfo storage node = nodes[nodeAddress];
        require(node.registered, "Not registered");
        uint256 slashAmount = (node.stake * slashingPercentage) / 100;
        node.stake -= slashAmount;
        node.reputation = node.reputation > 20 ? node.reputation - 20 : 0;
        emit NodeSlashed(nodeAddress, slashAmount, reason);
    }

    function updateReputation(address nodeAddress, bool taskSuccessful) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NodeInfo storage node = nodes[nodeAddress];
        require(node.registered, "Not registered");
        if (taskSuccessful) {
            node.tasksCompleted++;
            node.reputation = node.reputation < 95 ? node.reputation + 5 : 100;
        } else {
            node.reputation = node.reputation > 5 ? node.reputation - 5 : 0;
        }
    }

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
            if (
                node.capabilities.cpuCores >= minCPU && node.capabilities.ramGB >= minRAM
                    && (!requireGPU || node.capabilities.hasGPU) && node.reputation >= 30
                    && block.timestamp <= node.attestation.validUntil
                    && block.timestamp - node.lastActiveTime <= inactivityThreshold && (!preferGreen || node.isGreen)
            ) {
                temp[count++] = nodeAddr;
            }
        }
        suitableNodes = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            suitableNodes[i] = temp[i];
        }
    }

    function getNodeDetails(address nodeAddress)
        external
        view
        returns (NodeInfo memory info, uint256 greenMultiplier, uint256 aiScore)
    {
        info = nodes[nodeAddress];
        greenMultiplier = greenVerifier.getRewardMultiplier(nodeAddress);
        aiScore = aiOracle.nodeScores(nodeAddress);
    }

    function isNodeEligible(address nodeAddress) external view returns (bool) {
        NodeInfo memory node = nodes[nodeAddress];
        return node.registered && !slashedNodes[nodeAddress] && block.timestamp <= node.attestation.validUntil
            && block.timestamp - node.lastActiveTime <= inactivityThreshold && node.reputation >= 20;
    }

    // Compact compatibility functions
    function togglePowerSavingMode() external {
        NodeInfo storage node = nodes[msg.sender];
        require(node.registered && isMobileDevice[node.capabilities.deviceType], "Invalid");
        node.isPowerSaving = !node.isPowerSaving;
    }

    function getNodesByDeviceType(NodeDeviceType deviceType) external view returns (address[] memory) {
        address[] memory temp = new address[](activeNodes.length);
        uint256 count = 0;
        for (uint256 i = 0; i < activeNodes.length; i++) {
            if (nodes[activeNodes[i]].capabilities.deviceType == deviceType) temp[count++] = activeNodes[i];
        }
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }
        return result;
    }

    function updateActivity(address nodeAddress) external {
        require(
            nodes[nodeAddress].registered && (msg.sender == nodeAddress || hasRole(DEFAULT_ADMIN_ROLE, msg.sender)),
            "Unauthorized"
        );
        nodes[nodeAddress].lastActiveTime = block.timestamp;
    }

    function reportBatteryLevel(uint256 batteryLevel) external {
        NodeInfo storage node = nodes[msg.sender];
        require(node.registered && isMobileDevice[node.capabilities.deviceType] && batteryLevel <= 100, "Invalid");
        if (batteryLevel <= mobilePowerSaveThreshold && !node.isPowerSaving) node.isPowerSaving = true;
    }

    function canNodeHandleTask(address nodeAddress) external view returns (bool) {
        NodeInfo memory node = nodes[nodeAddress];
        return node.registered && node.activeTasks < node.deviceProfile.maxConcurrentTasks
            && (!isMobileDevice[node.capabilities.deviceType] || !node.isPowerSaving);
    }

    function incrementActiveTasks(address nodeAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(nodes[nodeAddress].registered, "Not registered");
        nodes[nodeAddress].activeTasks++;
    }

    function decrementActiveTasks(address nodeAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(nodes[nodeAddress].registered, "Not registered");
        nodes[nodeAddress].activeTasks--;
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
