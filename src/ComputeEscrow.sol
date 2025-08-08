// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title ComputeEscrow
 * @notice USDC (or any ERC20) escrow for job payments, controlled by JobManager
 */
contract ComputeEscrow is Initializable, AccessControlUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    bytes32 public constant ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN_ROLE");
    bytes32 public constant JOB_MANAGER_ROLE = keccak256("JOB_MANAGER_ROLE");

    IERC20 public paymentToken; // e.g., USDC on the target L2

    struct Escrow {
        address payer;
        address payee; // optional known upfront, can be zero until assignment
        uint256 amount;
        bool funded;
        bool released;
        bool refunded;
    }

    // jobId => escrow
    mapping(uint256 => Escrow) public escrows;

    event EscrowCreated(uint256 indexed jobId, address indexed payer, uint256 amount);
    event EscrowFunded(uint256 indexed jobId, address indexed payer, uint256 amount);
    event EscrowPayeeSet(uint256 indexed jobId, address indexed payee);
    event EscrowReleased(uint256 indexed jobId, address indexed payee, uint256 amount);
    event EscrowRefunded(uint256 indexed jobId, address indexed payer, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token, address initialOwner) public initializer {
        __AccessControl_init();
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        paymentToken = IERC20(_token);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ESCROW_ADMIN_ROLE, initialOwner);
    }

    function createEscrow(uint256 jobId, address payer, uint256 amount) external whenNotPaused onlyRole(JOB_MANAGER_ROLE) {
        require(escrows[jobId].payer == address(0), "Escrow exists");
        require(payer != address(0) && amount > 0, "Invalid params");

        escrows[jobId] = Escrow({
            payer: payer,
            payee: address(0),
            amount: amount,
            funded: false,
            released: false,
            refunded: false
        });

        emit EscrowCreated(jobId, payer, amount);
    }

    function fundEscrow(uint256 jobId) external nonReentrant whenNotPaused {
        Escrow storage e = escrows[jobId];
        require(e.payer != address(0), "No escrow");
        require(!e.funded && !e.released && !e.refunded, "Invalid state");
        require(msg.sender == e.payer, "Not payer");

        require(paymentToken.transferFrom(msg.sender, address(this), e.amount), "Transfer failed");
        e.funded = true;
        emit EscrowFunded(jobId, msg.sender, e.amount);
    }

    function setPayee(uint256 jobId, address payee) external whenNotPaused onlyRole(JOB_MANAGER_ROLE) {
        Escrow storage e = escrows[jobId];
        require(e.payer != address(0), "No escrow");
        require(!e.released && !e.refunded, "Closed");
        e.payee = payee;
        emit EscrowPayeeSet(jobId, payee);
    }

    function release(uint256 jobId, address payeeOverride) external nonReentrant whenNotPaused onlyRole(JOB_MANAGER_ROLE) {
        Escrow storage e = escrows[jobId];
        require(e.payer != address(0), "No escrow");
        require(e.funded && !e.released && !e.refunded, "Invalid state");
        address payee = payeeOverride != address(0) ? payeeOverride : e.payee;
        require(payee != address(0), "No payee");

        e.released = true;
        require(paymentToken.transfer(payee, e.amount), "Payout failed");
        emit EscrowReleased(jobId, payee, e.amount);
    }

    function refund(uint256 jobId) external nonReentrant whenNotPaused onlyRole(JOB_MANAGER_ROLE) {
        Escrow storage e = escrows[jobId];
        require(e.payer != address(0), "No escrow");
        require(e.funded && !e.released && !e.refunded, "Invalid state");

        e.refunded = true;
        require(paymentToken.transfer(e.payer, e.amount), "Refund failed");
        emit EscrowRefunded(jobId, e.payer, e.amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
