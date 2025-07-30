// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IZKVerifier.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// @title ZKTaskVerifier
// @notice Groth16 proof verifier for Tachyon Network task validation
// @dev Enables privacy-preserving proof of computation
//      Based on standard Ethereum Groth16 verifier with optimizations
//      Verification key is hardcoded after trusted setup ceremony
contract ZKTaskVerifier is IZKVerifier, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using Pairing for *;

    // Verification key components (set after trusted setup)
    struct VerifyingKey {
        Pairing.G1Point alpha;
        Pairing.G2Point beta;
        Pairing.G2Point gamma;
        Pairing.G2Point delta;
        Pairing.G1Point[] gamma_abc;
    }

    VerifyingKey verifyingKey;
    bool public initialized;
    bytes32 public verificationKeyHash;

    // Events
    event VerificationKeyUpdated(bytes32 indexed keyHash);
    event ProofVerified(address indexed verifier, bool result);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        // Initialize with a sample verification key (replace with actual after trusted setup)
        _initializeVerificationKey();
    }

    // @notice Initialize verification key (called once after trusted setup)
    function _initializeVerificationKey() internal {
        verifyingKey.alpha = Pairing.G1Point(
            0x1c76476f4def4bb94541d57ebba1193381ffa7aa76ada664dd31c16024c43f59,
            0x3034dd2920f673e204fee2811c678745fc819b55d3e9d294e45c9b03a76aef41
        );

        verifyingKey.beta = Pairing.G2Point(
            [
                0x209dd15ebff5d46c4bd888e51a93cf99a7329636c63514396b4a452003a35bf7,
                0x04bf11ca01483bfa8b34b43561848d28905960114c8ac04049af4b6315a41678
            ],
            [
                0x2bb8324af6cfc93537a2ad1a445cfd0ca2a71acd7ac41fadbf933c2a51be344d,
                0x120a2a4cf30c1bf9845f20c6fe39e07ea2cce61f0c9bb048165fe5e4de877550
            ]
        );

        verifyingKey.gamma = Pairing.G2Point(
            [
                0x111e129f1cf1097710d41c4ac70fcdfa5ba2023c6ff1cbeac322de49d1b6df7c,
                0x2032c61a830e3c17286de9462bf242fca2883585b93870a73853face6a6bf411
            ],
            [
                0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2,
                0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed
            ]
        );

        verifyingKey.delta = Pairing.G2Point(
            [
                0x17c139df0efee0f766bc0204762b774362e4ded88953a39ce849a8a7fa163fa9,
                0x01e0559bacb160664764a357af8a9fe70baa9258e0b959273ffc5718c6d4cc7c
            ],
            [
                0x03078754f25f3e60078d0f69370e15c75a54d0a2ef6d2a0270f7e0883d13fedc,
                0x2f47da3e83f50c2fa2e26fac9a691e8104cea092b4f160322e5aa5b7a993d269
            ]
        );

        verifyingKey.gamma_abc = new Pairing.G1Point[](5);
        verifyingKey.gamma_abc[0] = Pairing.G1Point(
            0x2e89718ad33c8bed92e210b3c9711443f4ef8b2f1c6f21db5b8080c2b5b93d6f,
            0x14b9b6ae3bdcf48de6d5a11c5b33f09e4a7ea1d66328053e25863d40833d7b0e
        );

        // Additional points for 4 public inputs
        verifyingKey.gamma_abc[1] = Pairing.G1Point(
            0x0c4261a23c1c250c8a23de78eb8cb8f22f0936a21fb893830e40c045f3196519,
            0x0fb775e15a26772c78285d9e8b5774f986389a3e90e0d44073fc0c5fb09fc062
        );

        verifyingKey.gamma_abc[2] = Pairing.G1Point(
            0x271bdee912be12c2a66b97ce19bb5142b6bb959d95a77e618033ffacd5e87b17,
            0x181617d5a5cf0e3e3c37baa4301e928e0a87d7032cc060b3c275f9c07c728d23
        );

        verifyingKey.gamma_abc[3] = Pairing.G1Point(
            0x29d7d22bc8495144b3bb88b8ee0c98c8b96d712af2a5ec3dc586d36502e1be22,
            0x0e3c690b049af4125ddebf5c2d5810e3c1e1e01f481242aecebe6a15f119a161
        );

        verifyingKey.gamma_abc[4] = Pairing.G1Point(
            0x1ded8980aacf14bed6895268e3e6b6d088f96b7db6d8d913e1e42e7a2c6b874e,
            0x0cd907c68ba128059a001e27bb7ed0e26d0ab38d2f0f5c76352be7c33c3d0c74
        );

        // Calculate and store verification key hash
        verificationKeyHash = keccak256(abi.encode(verifyingKey));
        initialized = true;

        emit VerificationKeyUpdated(verificationKeyHash);
    }

    // @notice Verify a Groth16 proof
    // @dev Public inputs: [taskHash, resultHash, nodeAddress, timestamp]
    function verifyProof(uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[4] memory input)
        public
        view
        override
        returns (bool)
    {
        require(initialized, "Verifier not initialized");

        Proof memory proof;
        proof.a = Pairing.G1Point(a[0], a[1]);
        proof.b = Pairing.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
        proof.c = Pairing.G1Point(c[0], c[1]);

        // Verify the proof
        uint256[] memory inputValues = new uint256[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            inputValues[i] = input[i];
        }

        bool result = verify(inputValues, proof);

        return result;
    }

    function verify(uint256[] memory input, Proof memory proof) internal view returns (bool) {
        uint256 snark_scalar_field = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
        VerifyingKey memory vk = verifyingKey;
        require(input.length + 1 == vk.gamma_abc.length, "Invalid input length");

        // Check input bounds
        for (uint256 i = 0; i < input.length; i++) {
            require(input[i] < snark_scalar_field, "Input exceeds field size");
        }

        // Compute the linear combination vk_x
        Pairing.G1Point memory vk_x = Pairing.G1Point(0, 0);
        for (uint256 i = 0; i < input.length; i++) {
            require(input[i] < snark_scalar_field, "verifier-gte-snark-scalar-field");
            vk_x = Pairing.addition(vk_x, Pairing.scalar_mul(vk.gamma_abc[i + 1], input[i]));
        }
        vk_x = Pairing.addition(vk_x, vk.gamma_abc[0]);

        // Pairing check
        return Pairing.pairing(Pairing.negate(proof.a), proof.b, vk.alpha, vk.beta, vk_x, vk.gamma, proof.c, vk.delta);
    }

    // @notice Get verification key hash
    function getVerificationKeyHash() external view override returns (bytes32) {
        return verificationKeyHash;
    }

    // @notice Check if verifier is initialized
    function isInitialized() external view override returns (bool) {
        return initialized;
    }

    // @notice Update verification key (only owner, use with extreme caution)
    function updateVerificationKey(
        uint256[2] memory alpha,
        uint256[2][2] memory beta,
        uint256[2][2] memory gamma,
        uint256[2][2] memory delta,
        uint256[2][] memory gamma_abc
    ) external onlyOwner {
        require(gamma_abc.length == 5, "Invalid gamma_abc length");

        verifyingKey.alpha = Pairing.G1Point(alpha[0], alpha[1]);
        verifyingKey.beta = Pairing.G2Point([beta[0][0], beta[0][1]], [beta[1][0], beta[1][1]]);
        verifyingKey.gamma = Pairing.G2Point([gamma[0][0], gamma[0][1]], [gamma[1][0], gamma[1][1]]);
        verifyingKey.delta = Pairing.G2Point([delta[0][0], delta[0][1]], [delta[1][0], delta[1][1]]);

        delete verifyingKey.gamma_abc;
        for (uint256 i = 0; i < gamma_abc.length; i++) {
            verifyingKey.gamma_abc.push(Pairing.G1Point(gamma_abc[i][0], gamma_abc[i][1]));
        }

        verificationKeyHash = keccak256(abi.encode(verifyingKey));
        emit VerificationKeyUpdated(verificationKeyHash);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Proof struct
    struct Proof {
        Pairing.G1Point a;
        Pairing.G2Point b;
        Pairing.G1Point c;
    }
}

// @title Pairing
// @notice Elliptic curve pairing operations for BN254
// @dev Precompiled contract calls for zkSNARK verification
library Pairing {
    struct G1Point {
        uint256 X;
        uint256 Y;
    }

    struct G2Point {
        uint256[2] X;
        uint256[2] Y;
    }

    // @return The generator of G1
    function P1() internal pure returns (G1Point memory) {
        return G1Point(1, 2);
    }

    // @return The generator of G2
    function P2() internal pure returns (G2Point memory) {
        return G2Point(
            [
                10857046999023057135944570762232829481370756359578518086990519993285655852781,
                11559732032986387107991004021392285783925812861821192530917403151452391805634
            ],
            [
                8495653923123431417604973247489272438418190587263600148770280649306958101930,
                4082367875863433681332203403145435568316851327593401208105741076214120093531
            ]
        );
    }

    // @return The negation of p, i.e. p.addition(p.negate()) should be zero.
    function negate(G1Point memory p) internal pure returns (G1Point memory) {
        uint256 q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
        if (p.X == 0 && p.Y == 0) {
            return G1Point(0, 0);
        }
        return G1Point(p.X, q - (p.Y % q));
    }

    // @return The sum of two points of G1
    function addition(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
        uint256[4] memory input;
        input[0] = p1.X;
        input[1] = p1.Y;
        input[2] = p2.X;
        input[3] = p2.Y;
        bool success;
        assembly {
            success := staticcall(sub(gas(), 2000), 6, input, 0xc0, r, 0x60)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "Pairing addition failed");
    }

    // @return The product of a point on G1 and a scalar
    function scalar_mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
        uint256[3] memory input;
        input[0] = p.X;
        input[1] = p.Y;
        input[2] = s;
        bool success;
        assembly {
            success := staticcall(sub(gas(), 2000), 7, input, 0x80, r, 0x60)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "Pairing scalar multiplication failed");
    }

    // @return The result of computing the pairing check
    function pairing(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2,
        G1Point memory c1,
        G2Point memory c2,
        G1Point memory d1,
        G2Point memory d2
    ) internal view returns (bool) {
        G1Point[4] memory p1 = [a1, b1, c1, d1];
        G2Point[4] memory p2 = [a2, b2, c2, d2];
        uint256 inputSize = 24;
        uint256[] memory input = new uint256[](inputSize);
        for (uint256 i = 0; i < 4; i++) {
            uint256 j = i * 6;
            input[j + 0] = p1[i].X;
            input[j + 1] = p1[i].Y;
            input[j + 2] = p2[i].X[0];
            input[j + 3] = p2[i].X[1];
            input[j + 4] = p2[i].Y[0];
            input[j + 5] = p2[i].Y[1];
        }
        uint256[1] memory out;
        bool success;
        assembly {
            success := staticcall(sub(gas(), 2000), 8, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "Pairing check failed");
        return out[0] != 0;
    }
}
