// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// @title TachyonToken
// @notice ERC20 utility token for Tachyon Network: used for task payments, node staking, and PoUW rewards.
// @dev Implements best practices from Consensys: modular design, access control, pausability, upgradability for security.
//      For quantum resistance: Uses UUPS proxy pattern for future upgrades to post-quantum cryptography (e.g., integrating XMSS or Dilithium signatures via Ethereum roadmap or oracles).
//      Current ECDSA is vulnerable to Shor's algorithm; plan migration to quantum-safe schemes (e.g., hash-based addresses or BLS aggregates).
//      Keccak-256 hashing provides Grover resistance with sufficient output size. Avoid timestamp dependencies for security.
//      Follows Consensys guidelines: simple logic, events for monitoring, role-based access, reentrancy guards implicit in OZ.
contract TachyonToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // @dev Initial supply and decimals set for network economics (e.g., rewards in PoUW).
    uint256 private constant INITIAL_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens

    // Events for transparency and monitoring (Consensys best practice)
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    // @dev Constructor disabled for upgradability.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // @notice Initializes the contract with roles and initial supply.
    // @dev Called once after deployment via proxy. Sets up roles and mints initial supply to owner.
    // @param initialOwner Address to receive initial supply and own the contract.
    function initialize(address initialOwner) public initializer {
        __ERC20_init("Tachyon Token", "TACH");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MINTER_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, initialOwner);

        _mint(initialOwner, INITIAL_SUPPLY);
        emit Minted(initialOwner, INITIAL_SUPPLY);
    }

    // @notice Mints new tokens for rewards (e.g., called by RewardManager.sol in PoUW validation).
    // @dev Restricted to MINTER_ROLE (e.g., RewardManager contract). Emits event for auditing.
    // @param to Recipient address.
    // @param amount Amount to mint.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit Minted(to, amount);
    }

    // @notice Burns tokens (e.g., for deflationary mechanics or staking penalties).
    // @dev Overrides ERC20Burnable; adds event.
    // @param amount Amount to burn from msg.sender.
    function burn(uint256 amount) public override {
        super.burn(amount);
        emit Burned(msg.sender, amount);
    }

    // @notice Burns tokens from a specific account (e.g., for slashing in NodeRegistry).
    // @dev Requires allowance; restricted if needed, but here open as per ERC20.
    // @param from Account to burn from.
    // @param amount Amount to burn.
    function burnFrom(address from, uint256 amount) public override {
        super.burnFrom(from, amount);
        emit Burned(from, amount);
    }

    // @notice Pauses all token transfers in emergencies (Consensys: emergency response).
    // @dev Restricted to PAUSER_ROLE.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    // @notice Unpauses token transfers.
    // @dev Restricted to PAUSER_ROLE.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // @dev Internal hook to enforce pause on transfers (from Pausable).
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
    }

    // @dev UUPS upgrade authorization: only owner can upgrade (for quantum resistance upgrades).
    // @param newImplementation Address of new implementation contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // @notice Version getter for upgradability tracking.
    // @return Contract version string.
    function version() public pure returns (string memory) {
        return "1.0.0"; // Update on upgrades, e.g., to quantum-safe version.
    }

    // Fallback and receive functions (Consensys: explicit rejection of unintended ETH).
    fallback() external payable {
        revert("TachyonToken: does not accept ETH");
    }

    receive() external payable {
        revert("TachyonToken: does not accept ETH");
    }
}
