// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/JobManager.sol";
import "../src/NodeRegistryCompact.sol";
import "../src/AIOracle.sol";
import "../src/TachyonToken.sol";

contract DebugJobCreation is Script {
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    address constant NODE_REGISTRY = 0xF619343016DD4c863D56A8bC8fDC033Dd023E9F7;
    address constant AI_ORACLE = 0xC891E58C0f7d3D23a26bf1E8433a263b72066577;
    address constant TACHYON_TOKEN = 0x2364b88237866CD8561866980bD2f12a6c14819E;

    function run() external {
        console.log("=== Debugging Job Creation Failure ===");

        JobManager jobManager = JobManager(JOB_MANAGER);
        NodeRegistryCompact nodeRegistry = NodeRegistryCompact(NODE_REGISTRY);
        AIOracle aiOracle = AIOracle(AI_ORACLE);
        TachyonToken tachyonToken = TachyonToken(payable(TACHYON_TOKEN));

        address userAddress = 0x7c17f9D9378a2aa5fB98BDc8E3b8aaF3c8eedd71;

        console.log("User address:", userAddress);
        console.log("JobManager:", JOB_MANAGER);
        console.log("NodeRegistry:", NODE_REGISTRY);
        console.log("AIOracle:", AI_ORACLE);
        console.log("TachyonToken:", TACHYON_TOKEN);

        // Check JobManager state
        console.log("\n=== JobManager State ===");
        console.log("Paused:", jobManager.paused());
        console.log("Min payment:", jobManager.minJobPayment());
        console.log("User has JOB_CREATOR_ROLE:", jobManager.hasRole(jobManager.JOB_CREATOR_ROLE(), userAddress));

        // Check user TACH balance and allowance
        console.log("\n=== User Token State ===");
        console.log("User TACH balance:", tachyonToken.balanceOf(userAddress));
        console.log("User allowance to JobManager:", tachyonToken.allowance(userAddress, JOB_MANAGER));

        // Check if there are active nodes
        console.log("\n=== Node Registry State ===");
        console.log("Total nodes registered:", nodeRegistry.totalNodes());

        // Check AIOracle state
        console.log("\n=== AIOracle State ===");
        console.log("LINK balance:", aiOracle.getLinkBalance());

        // Try to simulate job creation parameters
        console.log("\n=== Simulating Job Creation ===");

        // Check if getNodeDetails function exists and works
        address testNode = 0x7c17f9D9378a2aa5fB98BDc8E3b8aaF3c8eedd71; // Using user address as test
        // We'll just call it and see if it works
        console.log("Testing getNodeDetails function...");

        // Check current job count
        console.log("Total jobs created:", jobManager.totalJobsCreated());

        // Try to check specific requirements
        console.log("\n=== Checking Job Creation Requirements ===");
        console.log("Payment amount (50 TACH): 50000000000000000000");
        console.log("Minimum required:", jobManager.minJobPayment());
        console.log("Payment sufficient:", 50000000000000000000 >= jobManager.minJobPayment());

        // Check deadline calculation
        uint256 currentTime = block.timestamp;
        uint256 deadlineHours = 1;
        uint256 calculatedDeadline = currentTime + (deadlineHours * 3600);
        console.log("Current time:", currentTime);
        console.log("Deadline (1 hour):", calculatedDeadline);
        console.log(
            "Deadline reasonable:", calculatedDeadline > currentTime && calculatedDeadline <= currentTime + (48 * 3600)
        );
    }
}
