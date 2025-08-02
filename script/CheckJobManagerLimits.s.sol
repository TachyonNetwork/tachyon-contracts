// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckJobManagerLimits is Script {
    
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    
    function run() external view {
        console.log("=== Checking JobManager Limits ===");
        
        // Check max job duration
        bytes memory maxDurationData = abi.encodeWithSignature("maxJobDuration()");
        (bool success1, bytes memory result1) = JOB_MANAGER.staticcall(maxDurationData);
        if (success1 && result1.length >= 32) {
            uint256 maxDuration = abi.decode(result1, (uint256));
            console.log("Max job duration (seconds):", maxDuration);
            console.log("Max job duration (hours):", maxDuration / 3600);
            console.log("Max job duration (days):", maxDuration / 86400);
        }
        
        // Check job assignment timeout
        bytes memory timeoutData = abi.encodeWithSignature("jobAssignmentTimeout()");
        (bool success2, bytes memory result2) = JOB_MANAGER.staticcall(timeoutData);
        if (success2 && result2.length >= 32) {
            uint256 timeout = abi.decode(result2, (uint256));
            console.log("Job assignment timeout (seconds):", timeout);
            console.log("Job assignment timeout (hours):", timeout / 3600);
        }
        
        console.log("");
        console.log("Current time:", block.timestamp);
        console.log("48 hours from now:", block.timestamp + 48 hours);
        console.log("Difference:", 48 hours);
    }
}