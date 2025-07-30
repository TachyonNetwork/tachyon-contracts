// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/interfaces/IZKVerifier.sol";

// @title MockZKVerifier
// @notice Mock ZK verifier for testing purposes
// @dev Always returns true for valid test proofs
contract MockZKVerifier is IZKVerifier {
    bool public initialized = true;
    bytes32 public constant MOCK_VERIFICATION_KEY_HASH = keccak256("MOCK_VERIFICATION_KEY");

    // Mapping to control verification results in tests
    mapping(bytes32 => bool) public proofResults;
    bool public defaultResult = true;

    // Events
    event MockProofVerified(uint256[2] a, uint256[2][2] b, uint256[2] c, uint256[4] input, bool result);

    // @notice Set default verification result
    function setDefaultResult(bool _result) external {
        defaultResult = _result;
    }

    // @notice Set specific proof result
    function setProofResult(bytes32 proofHash, bool result) external {
        proofResults[proofHash] = result;
    }

    // @notice Mock verification - returns predetermined result
    function verifyProof(uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input)
        external
        view
        override
        returns (bool)
    {
        // Create proof hash from inputs
        bytes32 proofHash = keccak256(abi.encode(a, b, c, input));

        // Check if specific result is set
        if (proofResults[proofHash]) {
            return true;
        }

        // For testing: Accept proofs where a[0] == 1 as valid test proofs
        if (a[0] == 1) {
            return true;
        }

        return defaultResult;
    }

    // @notice Get mock verification key hash
    function getVerificationKeyHash() external pure override returns (bytes32) {
        return MOCK_VERIFICATION_KEY_HASH;
    }

    // @notice Check if verifier is initialized
    function isInitialized() external view override returns (bool) {
        return initialized;
    }

    // @notice Generate valid test proof components
    function generateValidProof(bytes32 taskId, bytes32 resultHash, address nodeAddress, uint256 timestamp)
        external
        pure
        returns (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input)
    {
        // Generate deterministic test proof components
        a[0] = 1; // Magic number for valid test proofs
        a[1] = uint256(keccak256(abi.encode(taskId, "a1"))) % 1000;

        b[0][0] = uint256(keccak256(abi.encode(taskId, "b00"))) % 1000;
        b[0][1] = uint256(keccak256(abi.encode(taskId, "b01"))) % 1000;
        b[1][0] = uint256(keccak256(abi.encode(taskId, "b10"))) % 1000;
        b[1][1] = uint256(keccak256(abi.encode(taskId, "b11"))) % 1000;

        c[0] = uint256(keccak256(abi.encode(taskId, "c0"))) % 1000;
        c[1] = uint256(keccak256(abi.encode(taskId, "c1"))) % 1000;

        // Public inputs
        input[0] = uint256(taskId);
        input[1] = uint256(resultHash);
        input[2] = uint256(uint160(nodeAddress));
        input[3] = timestamp;
    }
}
