// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckTransactionError is Script {
    
    function run() external view {
        // Check the failed transaction
        bytes32 txHash = 0x0a49fe72039923fe77635341c2e7aaf25134989a4173de20da544faeed3fb12e;
        
        console.log("=== Analyzing Failed Transaction ===");
        console.log("Transaction hash:", vm.toString(txHash));
        
        // Try to get transaction details
        // Note: This is a view-only analysis, we can't replay the exact transaction
        console.log("Transaction failed with status 0 (reverted)");
        console.log("Common causes:");
        console.log("1. Insufficient allowance or balance");
        console.log("2. Contract validation failure");
        console.log("3. Access control restriction");
        console.log("4. Contract paused state");
        console.log("5. Gas limit exceeded");
        
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Check JobManager contract state");
        console.log("2. Verify all contract addresses are correct");
        console.log("3. Check if contracts are paused");
        console.log("4. Verify user has required roles");
    }
}