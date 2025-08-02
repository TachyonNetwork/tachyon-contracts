// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/JobManager.sol";

contract SimulateJobCreation is Script {
    
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        JobManager jobManager = JobManager(JOB_MANAGER);
        
        console.log("=== Simulating Job Creation ===");
        
        // These are the exact parameters from the backend
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 4,
            minRamGB: 8,
            minStorageGB: 100,
            minBandwidthMbps: 100,
            requiresGPU: true,
            minGpuMemoryGB: 4,
            estimatedDurationMinutes: 60
        });
        
        uint256 payment = 50000000000000000000; // 50 TACH
        uint256 deadline = block.timestamp + 3600; // 1 hour from now
        string memory ipfsHash = "QmExampleMLModelHash123456789";
        bool preferGreenNodes = true;
        
        console.log("Job parameters:");
        console.log("Payment:", payment);
        console.log("Deadline:", deadline);
        console.log("Current time:", block.timestamp);
        console.log("Deadline valid:", deadline > block.timestamp);
        console.log("Prefer green nodes:", preferGreenNodes);
        
        // Try to create the job
        try jobManager.createJob(
            JobManager.JobType.ML_INFERENCE,
            JobManager.Priority.HIGH,
            requirements,
            payment,
            deadline,
            ipfsHash,
            preferGreenNodes
        ) returns (uint256 jobId) {
            console.log("SUCCESS: Job created with ID:", jobId);
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED with low level data:");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
    }
}