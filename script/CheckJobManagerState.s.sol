// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckJobManagerState is Script {
    address constant JOB_MANAGER = 0x425d6033e8495174b0D8c23f29b0CA0938a974Cd;
    address constant AI_ORACLE = 0xC891E58C0f7d3D23a26bf1E8433a263b72066577;
    address constant USER_ADDRESS = 0x7c17f9D9378a2aa5fB98BDc8E3b8aaF3c8eedd71;

    function run() external view {
        console.log("=== Checking JobManager State ===");
        console.log("JobManager address:", JOB_MANAGER);
        console.log("User address:", USER_ADDRESS);

        // Check if JobManager is paused
        bytes memory pausedData = abi.encodeWithSignature("paused()");
        (bool success1, bytes memory result1) = JOB_MANAGER.staticcall(pausedData);
        if (success1 && result1.length >= 32) {
            bool isPaused = abi.decode(result1, (bool));
            console.log("JobManager paused:", isPaused);
            if (isPaused) {
                console.log("ERROR: JobManager is paused!");
                return;
            }
        }

        // Check minimum job payment
        bytes memory minPaymentData = abi.encodeWithSignature("minJobPayment()");
        (bool success2, bytes memory result2) = JOB_MANAGER.staticcall(minPaymentData);
        if (success2 && result2.length >= 32) {
            uint256 minPayment = abi.decode(result2, (uint256));
            console.log("Minimum job payment:", minPayment);
        }

        // Check user roles
        bytes32 jobCreatorRole = keccak256("JOB_CREATOR_ROLE");
        bytes memory hasRoleData = abi.encodeWithSignature("hasRole(bytes32,address)", jobCreatorRole, USER_ADDRESS);
        (bool success3, bytes memory result3) = JOB_MANAGER.staticcall(hasRoleData);
        if (success3 && result3.length >= 32) {
            bool hasRole = abi.decode(result3, (bool));
            console.log("User has JOB_CREATOR_ROLE:", hasRole);
            if (!hasRole) {
                console.log("ERROR: User does not have JOB_CREATOR_ROLE!");
            }
        }

        // Check current AIOracle
        bytes memory aiOracleData = abi.encodeWithSignature("aiOracle()");
        (bool success4, bytes memory result4) = JOB_MANAGER.staticcall(aiOracleData);
        if (success4 && result4.length >= 32) {
            address currentAIOracle = abi.decode(result4, (address));
            console.log("Current AIOracle:", currentAIOracle);
            console.log("Expected AIOracle:", AI_ORACLE);
            console.log("AIOracle correct:", currentAIOracle == AI_ORACLE);
        }

        // Check if AIOracle is accessible
        bytes memory linkBalanceData = abi.encodeWithSignature("getLinkBalance()");
        (bool success5, bytes memory result5) = AI_ORACLE.staticcall(linkBalanceData);
        if (success5 && result5.length >= 32) {
            uint256 linkBalance = abi.decode(result5, (uint256));
            console.log("AIOracle LINK balance:", linkBalance);
            if (linkBalance == 0) {
                console.log("ERROR: AIOracle has no LINK tokens!");
            }
        }
    }
}
