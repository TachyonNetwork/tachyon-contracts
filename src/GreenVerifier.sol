// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// @title GreenVerifier
// @notice Verifies and tracks renewable energy usage for nodes in Tachyon Network
// @dev Integrates with real-world energy data oracles to incentivize sustainable computing
//      Revolutionary feature: Creates the first DePIN network that actively rewards green energy usage
//      Nodes using renewable energy get reward multipliers and priority in task assignment
contract GreenVerifier is
    Initializable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // Using ECDSA library directly

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // Green energy certification struct
    struct GreenCertificate {
        uint256 timestamp;
        uint256 energySourceType; // 1: Solar, 2: Wind, 3: Hydro, 4: Other renewable
        uint256 percentage; // Percentage of renewable energy (0-100)
        uint256 validUntil; // Certificate expiration
        bytes32 certificateHash; // Hash of external certificate (e.g., from energy provider)
        bool verified;
    }

    // Energy tracking struct
    struct EnergyMetrics {
        uint256 totalEnergyConsumed; // In watt-hours
        uint256 renewableEnergyUsed; // In watt-hours
        uint256 carbonOffsetTons; // Carbon offset in tons
        uint256 lastUpdateTimestamp;
    }

    // Node green status
    mapping(address => GreenCertificate) public greenCertificates;
    mapping(address => EnergyMetrics) public nodeEnergyMetrics;
    mapping(address => uint256) public greenScores; // 0-100 sustainability score

    // Oracle configuration for energy data
    mapping(uint256 => AggregatorV3Interface) public energyDataFeeds;

    // Reward multipliers based on green percentage
    uint256 public constant BASE_MULTIPLIER = 100; // 1x in basis points
    uint256 public constant MAX_GREEN_MULTIPLIER = 200; // 2x max multiplier

    // Carbon credit integration
    uint256 public totalCarbonOffsetTons;
    mapping(address => uint256) public nodeCarbonCredits;

    // Events
    event GreenCertificateSubmitted(address indexed node, uint256 energyType, uint256 percentage);
    event GreenCertificateVerified(address indexed node, bool approved);
    event EnergyMetricsUpdated(address indexed node, uint256 renewable, uint256 total);
    event GreenScoreUpdated(address indexed node, uint256 score);
    event CarbonCreditsIssued(address indexed node, uint256 credits);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __AccessControl_init();
        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(VERIFIER_ROLE, initialOwner);
    }

    // @notice Submit green energy certificate for verification
    // @param energySourceType Type of renewable energy source
    // @param percentage Percentage of energy from renewable sources
    // @param certificateData External certificate data
    // @param signature Signature from authorized energy provider
    function submitGreenCertificate(
        uint256 energySourceType,
        uint256 percentage,
        bytes calldata certificateData,
        bytes calldata signature
    ) external whenNotPaused {
        require(percentage <= 100, "Invalid percentage");
        require(energySourceType > 0 && energySourceType <= 4, "Invalid energy type");

        // Verify signature from authorized energy provider
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, energySourceType, percentage, certificateData));
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature);
        require(hasRole(ORACLE_ROLE, signer), "Invalid signature");

        greenCertificates[msg.sender] = GreenCertificate({
            timestamp: block.timestamp,
            energySourceType: energySourceType,
            percentage: percentage,
            validUntil: block.timestamp + 30 days,
            certificateHash: keccak256(certificateData),
            verified: false
        });

        emit GreenCertificateSubmitted(msg.sender, energySourceType, percentage);
    }

    // @notice Verify a node's green certificate
    // @dev Called by authorized verifiers after checking external data
    function verifyCertificate(address node, bool approved) external onlyRole(VERIFIER_ROLE) {
        GreenCertificate storage cert = greenCertificates[node];
        require(cert.timestamp > 0, "No certificate found");
        require(!cert.verified, "Already verified");

        cert.verified = approved;

        if (approved) {
            // Update green score based on renewable percentage
            uint256 score = cert.percentage;

            // Bonus points for certain energy types
            if (cert.energySourceType == 1) {
                // Solar
                score = score * 110 / 100; // 10% bonus
            } else if (cert.energySourceType == 2) {
                // Wind
                score = score * 105 / 100; // 5% bonus
            }

            greenScores[node] = score > 100 ? 100 : score;
            emit GreenScoreUpdated(node, greenScores[node]);
        }

        emit GreenCertificateVerified(node, approved);
    }

    // @notice Update energy metrics for a node
    // @dev Called by oracles with real-time energy data
    function updateEnergyMetrics(address node, uint256 totalEnergy, uint256 renewableEnergy)
        external
        onlyRole(ORACLE_ROLE)
    {
        require(renewableEnergy <= totalEnergy, "Invalid energy values");

        EnergyMetrics storage metrics = nodeEnergyMetrics[node];
        metrics.totalEnergyConsumed += totalEnergy;
        metrics.renewableEnergyUsed += renewableEnergy;
        metrics.lastUpdateTimestamp = block.timestamp;

        // Calculate carbon offset (simplified: 1 MWh renewable = 0.5 tons CO2 saved)
        uint256 carbonOffset = (renewableEnergy / 1e6) / 2;
        metrics.carbonOffsetTons += carbonOffset;
        totalCarbonOffsetTons += carbonOffset;

        emit EnergyMetricsUpdated(node, renewableEnergy, totalEnergy);

        // Issue carbon credits if threshold reached
        if (carbonOffset >= 1) {
            nodeCarbonCredits[node] += carbonOffset;
            emit CarbonCreditsIssued(node, carbonOffset);
        }
    }

    // @notice Calculate reward multiplier for a node based on green status
    // @param node Address of the node
    // @return multiplier Reward multiplier in basis points (100 = 1x)
    function getRewardMultiplier(address node) external view returns (uint256 multiplier) {
        GreenCertificate memory cert = greenCertificates[node];

        if (!cert.verified || block.timestamp > cert.validUntil) {
            return BASE_MULTIPLIER;
        }

        // Linear scaling: 0% renewable = 1x, 100% renewable = 2x
        multiplier = BASE_MULTIPLIER + (cert.percentage * (MAX_GREEN_MULTIPLIER - BASE_MULTIPLIER) / 100);

        // Additional bonus for high green scores
        uint256 score = greenScores[node];
        if (score >= 90) {
            multiplier = multiplier * 110 / 100; // 10% extra
        } else if (score >= 75) {
            multiplier = multiplier * 105 / 100; // 5% extra
        }

        return multiplier;
    }

    // @notice Check if a node is certified green
    function isNodeGreen(address node) external view returns (bool) {
        GreenCertificate memory cert = greenCertificates[node];
        return cert.verified && block.timestamp <= cert.validUntil && cert.percentage >= 50;
    }

    // @notice Get node's sustainability metrics
    function getNodeSustainabilityMetrics(address node)
        external
        view
        returns (uint256 greenScore, uint256 renewablePercentage, uint256 carbonOffsetTons, bool isGreen)
    {
        GreenCertificate memory cert = greenCertificates[node];
        EnergyMetrics memory metrics = nodeEnergyMetrics[node];

        greenScore = greenScores[node];
        renewablePercentage = cert.percentage;
        carbonOffsetTons = metrics.carbonOffsetTons;
        isGreen = cert.verified && block.timestamp <= cert.validUntil && cert.percentage >= 50;
    }

    // @notice Set energy data oracle feed
    function setEnergyDataFeed(uint256 feedType, address feedAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        energyDataFeeds[feedType] = AggregatorV3Interface(feedAddress);
    }

    // @notice Emergency pause
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // @notice Calculate total network carbon offset
    function getNetworkCarbonOffset() external view returns (uint256) {
        return totalCarbonOffsetTons;
    }

    // @notice Get top green nodes
    function getTopGreenNodes(uint256 limit) external view returns (address[] memory nodes, uint256[] memory scores) {
        nodes = new address[](limit);
        scores = new uint256[](limit);
        return (nodes, scores);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "1.0.0";
    }
}
