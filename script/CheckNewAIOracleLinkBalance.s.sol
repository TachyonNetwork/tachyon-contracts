// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckNewAIOracleLinkBalance is Script {
    
    // New AIOracle and correct LINK token
    address constant NEW_AI_ORACLE = 0xC891E58C0f7d3D23a26bf1E8433a263b72066577;
    address constant CORRECT_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    
    function run() external view {
        console.log("=== Checking New AIOracle LINK Balance ===");
        console.log("New AIOracle address:", NEW_AI_ORACLE);
        console.log("Correct LINK token address:", CORRECT_LINK_TOKEN);
        
        // Check LINK balance
        bytes memory balanceData = abi.encodeWithSignature("balanceOf(address)", NEW_AI_ORACLE);
        (bool success, bytes memory result) = CORRECT_LINK_TOKEN.staticcall(balanceData);
        
        if (success && result.length >= 32) {
            uint256 balance = abi.decode(result, (uint256));
            console.log("New AIOracle LINK balance (raw):", balance);
            
            if (balance > 0) {
                // Calculate human readable balance (LINK has 18 decimals)
                uint256 linkAmount = balance / 1e18;
                uint256 linkDecimals = (balance % 1e18) / 1e15; // 3 decimal places
                
                console.log("SUCCESS: New AIOracle has LINK tokens!");
                console.log("Balance (integer part):", linkAmount);
                console.log("Balance (decimal part):", linkDecimals);
                console.log("");
                console.log("=== Ready for Job Creation ===");
                console.log("You can now test job creation with the new AIOracle");
            } else {
                console.log("ERROR: New AIOracle has no LINK tokens");
                console.log("Please send LINK tokens to:", NEW_AI_ORACLE);
            }
        } else {
            console.log("ERROR: Failed to check LINK balance");
        }
    }
}