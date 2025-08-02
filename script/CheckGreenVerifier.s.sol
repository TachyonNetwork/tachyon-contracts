// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckGreenVerifier is Script {
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    address constant GREEN_VERIFIER_FROM_DEPLOY = 0x90B25A51c7d9693bb56B4964c5c4a32F7E94e025;

    function run() external view {
        console.log("=== Checking GreenVerifier Configuration ===");
        console.log("JobManager address:", JOB_MANAGER);

        // Check GreenVerifier address in JobManager
        bytes memory greenVerifierData = abi.encodeWithSignature("greenVerifier()");
        (bool success, bytes memory result) = JOB_MANAGER.staticcall(greenVerifierData);

        if (success && result.length >= 32) {
            address greenVerifier = abi.decode(result, (address));
            console.log("GreenVerifier in JobManager:", greenVerifier);
            console.log("GreenVerifier from deployments:", GREEN_VERIFIER_FROM_DEPLOY);

            if (greenVerifier == address(0)) {
                console.log("ERROR: GreenVerifier is not set (address 0)!");
                console.log("This might be causing job creation to fail");
            } else if (greenVerifier != GREEN_VERIFIER_FROM_DEPLOY) {
                console.log("WARNING: GreenVerifier address mismatch!");
            } else {
                console.log("GreenVerifier address is correct");

                // Check if we can call greenVerifier
                bytes memory checkData =
                    abi.encodeWithSignature("getRewardMultiplier(address)", 0x7c17f9D9378a2aa5fB98BDc8E3b8aaF3c8eedd71);
                (bool success2, bytes memory result2) = greenVerifier.staticcall(checkData);

                if (success2) {
                    console.log("GreenVerifier is accessible");
                } else {
                    console.log("ERROR: Cannot access GreenVerifier functions");
                }
            }
        } else {
            console.log("ERROR: Failed to get GreenVerifier address");
        }
    }
}
