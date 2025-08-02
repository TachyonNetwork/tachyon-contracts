// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract SimpleLinkCheck is Script {
    function run() external view {
        address LINK_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        address AI_ORACLE = 0x5B71b4Ee99664bD986d741F617838b5e9988dCD1;

        console.log("=== LINK Balance Check ===");
        console.log("AIOracle address:", AI_ORACLE);
        console.log("LINK token address:", LINK_TOKEN);

        // Check LINK balance using low-level call
        bytes memory data = abi.encodeWithSignature("balanceOf(address)", AI_ORACLE);
        (bool success, bytes memory result) = LINK_TOKEN.staticcall(data);

        if (success && result.length >= 32) {
            uint256 balance = abi.decode(result, (uint256));
            console.log("AIOracle LINK balance (raw):", balance);

            if (balance > 0) {
                console.log("SUCCESS: AIOracle has LINK tokens");
            } else {
                console.log("ERROR: AIOracle has no LINK tokens");
            }
        } else {
            console.log("ERROR: Failed to check LINK balance");
        }
    }
}
