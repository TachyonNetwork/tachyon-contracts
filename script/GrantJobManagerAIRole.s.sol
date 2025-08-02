// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/AIOracle.sol";

contract GrantJobManagerAIRole is Script {
    
    address constant AI_ORACLE = 0xC891E58C0f7d3D23a26bf1E8433a263b72066577;
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Granting AI_CONSUMER_ROLE to JobManager ===");
        console.log("AIOracle:", AI_ORACLE);
        console.log("JobManager:", JOB_MANAGER);
        
        AIOracle aiOracle = AIOracle(AI_ORACLE);
        
        bytes32 aiConsumerRole = aiOracle.AI_CONSUMER_ROLE();
        console.log("AI_CONSUMER_ROLE:");
        console.logBytes32(aiConsumerRole);
        
        // Check if JobManager already has the role
        bool hasRole = aiOracle.hasRole(aiConsumerRole, JOB_MANAGER);
        console.log("JobManager has AI_CONSUMER_ROLE:", hasRole);
        
        if (!hasRole) {
            console.log("Granting AI_CONSUMER_ROLE to JobManager...");
            aiOracle.grantRole(aiConsumerRole, JOB_MANAGER);
            console.log("SUCCESS: Role granted!");
        } else {
            console.log("JobManager already has AI_CONSUMER_ROLE");
        }
        
        // Verify the role was granted
        bool hasRoleAfter = aiOracle.hasRole(aiConsumerRole, JOB_MANAGER);
        console.log("JobManager has AI_CONSUMER_ROLE after:", hasRoleAfter);
        
        vm.stopBroadcast();
    }
}