// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// @title IZKVerifier
// @notice Interface for zero-knowledge proof verification in Tachyon Network
// @dev Implements Groth16 proof verification for private task validation
//      Nodes can prove they completed computations without revealing sensitive data
interface IZKVerifier {
    // @notice Verifies a Groth16 proof
    // @param a First part of the proof (G1 point)
    // @param b Second part of the proof (G2 point)
    // @param c Third part of the proof (G1 point)
    // @param input Public inputs for verification
    // @return bool True if proof is valid
    function verifyProof(uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input)
        external
        view
        returns (bool);

    // @notice Get the verification key hash for transparency
    // @return bytes32 Hash of the current verification key
    function getVerificationKeyHash() external view returns (bytes32);

    // @notice Check if the verifier is properly initialized
    // @return bool True if ready to verify proofs
    function isInitialized() external view returns (bool);
}
