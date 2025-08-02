// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckJobManagerAIOracle is Script {
    
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    address constant NEW_AI_ORACLE = 0xC891E58C0f7d3D23a26bf1E8433a263b72066577;
    address constant OLD_AI_ORACLE = 0xFa62d464be301ed9378312fc34d82B2121311fE8;
    
    function run() external view {
        console.log("=== Checking JobManager AIOracle Configuration ===");
        console.log("JobManager address:", JOB_MANAGER);
        console.log("New AIOracle address:", NEW_AI_ORACLE);
        console.log("Old AIOracle address:", OLD_AI_ORACLE);
        
        // Check which AIOracle JobManager is using
        bytes memory aiOracleData = abi.encodeWithSignature("aiOracle()");
        (bool success, bytes memory result) = JOB_MANAGER.staticcall(aiOracleData);
        
        if (success && result.length >= 32) {
            address currentAIOracle = abi.decode(result, (address));
            console.log("Current AIOracle in JobManager:", currentAIOracle);
            
            if (currentAIOracle == NEW_AI_ORACLE) {
                console.log("SUCCESS: JobManager is using the new AIOracle!");
            } else if (currentAIOracle == OLD_AI_ORACLE) {
                console.log("ERROR: JobManager is still using the old AIOracle!");
                console.log("Need to update JobManager configuration");
            } else {
                console.log("WARNING: JobManager is using a different AIOracle:", currentAIOracle);
            }
        } else {
            console.log("ERROR: Failed to get AIOracle address from JobManager");
        }
    }
}