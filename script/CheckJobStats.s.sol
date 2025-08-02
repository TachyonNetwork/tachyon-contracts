// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckJobStats is Script {
    
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    
    function run() external view {
        console.log("=== Checking JobManager Statistics ===");
        console.log("JobManager address:", JOB_MANAGER);
        
        // Check total jobs created
        bytes memory totalJobsData = abi.encodeWithSignature("totalJobsCreated()");
        (bool success1, bytes memory result1) = JOB_MANAGER.staticcall(totalJobsData);
        if (success1 && result1.length >= 32) {
            uint256 totalJobs = abi.decode(result1, (uint256));
            console.log("Total jobs created:", totalJobs);
        }
        
        // Check total jobs completed
        bytes memory completedJobsData = abi.encodeWithSignature("totalJobsCompleted()");
        (bool success2, bytes memory result2) = JOB_MANAGER.staticcall(completedJobsData);
        if (success2 && result2.length >= 32) {
            uint256 completedJobs = abi.decode(result2, (uint256));
            console.log("Total jobs completed:", completedJobs);
        }
        
        // Check next job ID
        bytes memory nextJobIdData = abi.encodeWithSignature("nextJobId()");
        (bool success3, bytes memory result3) = JOB_MANAGER.staticcall(nextJobIdData);
        if (success3 && result3.length >= 32) {
            uint256 nextJobId = abi.decode(result3, (uint256));
            console.log("Next job ID:", nextJobId);
        }
        
        // Get job statistics
        bytes memory jobStatsData = abi.encodeWithSignature("getJobStatistics()");
        (bool success4, bytes memory result4) = JOB_MANAGER.staticcall(jobStatsData);
        if (success4 && result4.length >= 160) { // 5 uint256 values = 160 bytes
            (uint256 total, uint256 completed, uint256 active, uint256 completionRate, uint256 avgGreenJobs) = 
                abi.decode(result4, (uint256, uint256, uint256, uint256, uint256));
            console.log("=== Job Statistics ===");
            console.log("Total:", total);
            console.log("Completed:", completed);
            console.log("Active:", active);
            console.log("Completion rate:", completionRate, "%");
            console.log("Green jobs percentage:", avgGreenJobs, "%");
        }
        
        // Check a few specific jobs to see if they exist
        for (uint256 i = 1; i <= 5; i++) {
            bytes memory jobData = abi.encodeWithSignature("jobs(uint256)", i);
            (bool success, bytes memory result) = JOB_MANAGER.staticcall(jobData);
            if (success) {
                console.log("Job", i, "exists:", result.length > 0);
            }
        }
    }
}