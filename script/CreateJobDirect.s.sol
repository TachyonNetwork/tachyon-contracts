// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/JobManager.sol";
import "../src/TachyonToken.sol";

contract CreateJobDirect is Script {
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    address constant TACHYON_TOKEN = 0x2e36816eD13a9C8DE8fF3c09FF2B636d20290841;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Creating Job Directly ===");
        console.log("Deployer:", deployer);
        console.log("JobManager:", JOB_MANAGER);

        JobManager jobManager = JobManager(JOB_MANAGER);
        TachyonToken tachyonToken = TachyonToken(payable(TACHYON_TOKEN));

        // Check balance
        uint256 balance = tachyonToken.balanceOf(deployer);
        console.log("TACH balance:", balance);

        // Approve spending
        uint256 payment = 25 ether; // 25 TACH
        console.log("Approving", payment, "TACH");
        tachyonToken.approve(JOB_MANAGER, payment);

        // Create job
        JobManager.ResourceRequirements memory requirements = JobManager.ResourceRequirements({
            minCpuCores: 2,
            minRamGB: 4,
            minStorageGB: 50,
            minBandwidthMbps: 50,
            requiresGPU: false,
            minGpuMemoryGB: 0,
            estimatedDurationMinutes: 120
        });

        console.log("Creating job...");

        try jobManager.createJob(
            JobManager.JobType.DATA_PROCESSING,
            JobManager.Priority.NORMAL,
            requirements,
            payment,
            block.timestamp + 48 hours,
            "QmExampleDataProcessingHash987654321",
            false // preferGreenNodes
        ) returns (uint256 jobId) {
            console.log("SUCCESS: Job created with ID:", jobId);
        } catch Error(string memory reason) {
            console.log("ERROR: Job creation failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: Job creation failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}
