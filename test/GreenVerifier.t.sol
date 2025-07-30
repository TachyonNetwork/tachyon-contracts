// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../src/GreenVerifier.sol";

contract GreenVerifierTest is Test {
    GreenVerifier public greenVerifier;

    address public owner = address(0x1);
    address public verifier = address(0x2);
    address public node1 = address(0x4);

    uint256 public oraclePrivateKey = 999;
    address public oracleAddress;

    event GreenCertificateSubmitted(address indexed node, uint256 energyType, uint256 percentage);
    event GreenCertificateVerified(address indexed node, bool approved);

    function setUp() public {
        vm.startPrank(owner);

        oracleAddress = vm.addr(oraclePrivateKey);

        // Deploy GreenVerifier
        GreenVerifier greenImpl = new GreenVerifier();
        bytes memory initData = abi.encodeWithSelector(GreenVerifier.initialize.selector, owner);
        ERC1967Proxy greenProxy = new ERC1967Proxy(address(greenImpl), initData);
        greenVerifier = GreenVerifier(address(greenProxy));

        // Setup roles
        greenVerifier.grantRole(greenVerifier.VERIFIER_ROLE(), verifier);
        greenVerifier.grantRole(greenVerifier.ORACLE_ROLE(), oracleAddress);

        vm.stopPrank();
    }

    function testInitialization() public view {
        assertEq(greenVerifier.owner(), owner);
        assertTrue(greenVerifier.hasRole(greenVerifier.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(greenVerifier.hasRole(greenVerifier.VERIFIER_ROLE(), verifier));
        assertTrue(greenVerifier.hasRole(greenVerifier.ORACLE_ROLE(), oracleAddress));
    }

    function testSubmitGreenCertificate() public {
        uint256 energyType = 1; // Solar
        uint256 percentage = 85; // 85% renewable
        bytes memory certData = "renewable-energy-certificate-data";

        // Create message hash and sign it with oracle's key
        bytes32 messageHash = keccak256(abi.encodePacked(node1, energyType, percentage, certData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);

        vm.expectEmit(true, false, false, true);
        emit GreenCertificateSubmitted(node1, energyType, percentage);

        greenVerifier.submitGreenCertificate(energyType, percentage, certData, signature);

        // Verify certificate was stored
        (
            uint256 timestamp,
            uint256 storedEnergyType,
            uint256 storedPercentage,
            uint256 validUntil,
            bytes32 certificateHash,
            bool isVerified
        ) = greenVerifier.greenCertificates(node1);

        assertEq(storedEnergyType, energyType);
        assertEq(storedPercentage, percentage);
        assertTrue(timestamp > 0);
        assertTrue(validUntil > timestamp);
        assertTrue(certificateHash != bytes32(0));
        assertFalse(isVerified); // Not verified yet

        vm.stopPrank();
    }

    function testSubmitGreenCertificateInvalidSignature() public {
        uint256 energyType = 1;
        uint256 percentage = 85;
        bytes memory certData = "renewable-energy-certificate-data";

        // Create invalid signature (wrong message)
        bytes32 wrongMessage = keccak256("wrong-message");
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(wrongMessage);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);
        vm.expectRevert("Invalid signature");
        greenVerifier.submitGreenCertificate(energyType, percentage, certData, invalidSignature);
        vm.stopPrank();
    }

    function testSubmitGreenCertificateInvalidPercentage() public {
        uint256 energyType = 1;
        uint256 invalidPercentage = 101; // > 100%
        bytes memory certData = "renewable-energy-certificate-data";

        bytes32 messageHash = keccak256(abi.encodePacked(node1, energyType, invalidPercentage, certData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);
        vm.expectRevert("Invalid percentage");
        greenVerifier.submitGreenCertificate(energyType, invalidPercentage, certData, signature);
        vm.stopPrank();
    }

    function testSubmitGreenCertificateInvalidEnergyType() public {
        uint256 invalidEnergyType = 0; // Invalid (must be 1-4)
        uint256 percentage = 80;
        bytes memory certData = "renewable-energy-certificate-data";

        bytes32 messageHash = keccak256(abi.encodePacked(node1, invalidEnergyType, percentage, certData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);
        vm.expectRevert("Invalid energy type");
        greenVerifier.submitGreenCertificate(invalidEnergyType, percentage, certData, signature);
        vm.stopPrank();
    }

    function testVerifyCertificate() public {
        // Submit certificate first
        uint256 energyType = 2; // Wind
        uint256 percentage = 90;
        bytes memory certData = "wind-energy-certificate";

        bytes32 messageHash = keccak256(abi.encodePacked(node1, energyType, percentage, certData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(energyType, percentage, certData, signature);
        vm.stopPrank();

        // Verify certificate
        vm.startPrank(verifier);

        vm.expectEmit(true, false, false, true);
        emit GreenCertificateVerified(node1, true);

        greenVerifier.verifyCertificate(node1, true);

        // Check verification status
        (,,,,, bool isVerified) = greenVerifier.greenCertificates(node1);
        assertTrue(isVerified);

        vm.stopPrank();
    }

    function testRejectCertificate() public {
        // Submit certificate first
        uint256 energyType = 1;
        uint256 percentage = 75;
        bytes memory certData = "questionable-certificate";

        bytes32 messageHash = keccak256(abi.encodePacked(node1, energyType, percentage, certData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(energyType, percentage, certData, signature);
        vm.stopPrank();

        // Reject certificate
        vm.startPrank(verifier);

        vm.expectEmit(true, false, false, true);
        emit GreenCertificateVerified(node1, false);

        greenVerifier.verifyCertificate(node1, false);

        // Check verification status
        (,,,,, bool isVerified) = greenVerifier.greenCertificates(node1);
        assertFalse(isVerified);

        vm.stopPrank();
    }

    function testGetRewardMultiplier() public {
        // Test default multiplier (no certificate)
        uint256 multiplier = greenVerifier.getRewardMultiplier(node1);
        assertEq(multiplier, 100); // Default 100%

        // Submit and verify certificate
        uint256 energyType = 3; // Hydro
        uint256 percentage = 95;
        bytes memory certData = "hydro-energy-certificate";

        bytes32 messageHash = keccak256(abi.encodePacked(node1, energyType, percentage, certData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(energyType, percentage, certData, signature);
        vm.stopPrank();

        vm.startPrank(verifier);
        greenVerifier.verifyCertificate(node1, true);
        vm.stopPrank();

        // Check reward multiplier with verified certificate
        multiplier = greenVerifier.getRewardMultiplier(node1);
        assertTrue(multiplier > 100); // Should be > 100% with green certificate
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);

        greenVerifier.pause();
        assertTrue(greenVerifier.paused());

        // Should not be able to submit certificates when paused
        vm.stopPrank();
        vm.startPrank(node1);
        vm.expectRevert("Pausable: paused");
        greenVerifier.submitGreenCertificate(1, 80, "test", "signature");
        vm.stopPrank();

        vm.startPrank(owner);
        greenVerifier.unpause();
        assertFalse(greenVerifier.paused());
        vm.stopPrank();
    }

    function testAccessControl() public {
        // Submit certificate first
        uint256 energyType = 1;
        uint256 percentage = 80;
        bytes memory certData = "test-certificate";

        bytes32 messageHash = keccak256(abi.encodePacked(node1, energyType, percentage, certData));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(energyType, percentage, certData, signature);
        vm.stopPrank();

        // Non-verifier should not be able to verify certificates
        vm.startPrank(address(0x999));
        vm.expectRevert();
        greenVerifier.verifyCertificate(node1, true);
        vm.stopPrank();
    }

    function testCertificateOverwrite() public {
        // Submit first certificate
        uint256 energyType1 = 1;
        uint256 percentage1 = 70;
        bytes memory certData1 = "first-certificate";

        bytes32 messageHash1 = keccak256(abi.encodePacked(node1, energyType1, percentage1, certData1));
        bytes32 ethSignedMessageHash1 = MessageHashUtils.toEthSignedMessageHash(messageHash1);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(oraclePrivateKey, ethSignedMessageHash1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(energyType1, percentage1, certData1, signature1);
        vm.stopPrank();

        // Submit second certificate (should overwrite)
        uint256 energyType2 = 2;
        uint256 percentage2 = 85;
        bytes memory certData2 = "updated-certificate";

        bytes32 messageHash2 = keccak256(abi.encodePacked(node1, energyType2, percentage2, certData2));
        bytes32 ethSignedMessageHash2 = MessageHashUtils.toEthSignedMessageHash(messageHash2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(oraclePrivateKey, ethSignedMessageHash2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        vm.startPrank(node1);
        greenVerifier.submitGreenCertificate(energyType2, percentage2, certData2, signature2);
        vm.stopPrank();

        // Verify the second certificate overwrote the first
        (
            uint256 timestamp,
            uint256 storedEnergyType,
            uint256 storedPercentage,
            uint256 validUntil,
            bytes32 certificateHash,
            bool isVerified
        ) = greenVerifier.greenCertificates(node1);

        assertEq(storedEnergyType, energyType2);
        assertEq(storedPercentage, percentage2);
        assertFalse(isVerified); // New certificate not verified yet
    }
}
