// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/JobManager.sol";

contract UpdateJobManagerAIOracle is Script {
    
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    address constant NEW_AI_ORACLE = 0xC891E58C0f7d3D23a26bf1E8433a263b72066577;
    address constant OLD_AI_ORACLE = 0xFa62d464be301ed9378312fc34d82B2121311fE8;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Updating JobManager AIOracle Address ===");
        console.log("Deployer address:", deployer);
        console.log("JobManager address:", JOB_MANAGER);
        console.log("Old AIOracle address:", OLD_AI_ORACLE);
        console.log("New AIOracle address:", NEW_AI_ORACLE);
        
        JobManager jobManager = JobManager(JOB_MANAGER);
        
        // Check current AIOracle
        address currentAIOracle = address(jobManager.aiOracle());
        console.log("Current AIOracle in JobManager:", currentAIOracle);
        
        if (currentAIOracle == NEW_AI_ORACLE) {
            console.log("JobManager already uses the new AIOracle!");
            vm.stopBroadcast();
            return;
        }
        
        // Update JobManager to use new AIOracle
        console.log("Updating JobManager to use new AIOracle...");
        jobManager.updateContractAddresses(
            address(0), // Keep current TachyonToken
            address(0), // Keep current NodeRegistry
            NEW_AI_ORACLE, // Update AIOracle
            address(0)  // Keep current GreenVerifier
        );
        
        // Verify the update
        address updatedAIOracle = address(jobManager.aiOracle());
        console.log("Updated AIOracle in JobManager:", updatedAIOracle);
        
        if (updatedAIOracle == NEW_AI_ORACLE) {
            console.log("SUCCESS: JobManager now uses the new AIOracle!");
            console.log("");
            console.log("=== Ready for Job Creation ===");
            console.log("JobManager is now configured with the correct AIOracle");
            console.log("You can now test job creation successfully");
        } else {
            console.log("ERROR: Failed to update AIOracle in JobManager");
        }
        
        vm.stopBroadcast();
    }
}