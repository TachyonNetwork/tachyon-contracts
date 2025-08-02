// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract DiagnoseLinkIssue is Script {
    // Base Sepolia addresses
    address constant AI_ORACLE = 0x5B71b4Ee99664bD986d741F617838b5e9988dCD1;
    address constant WRONG_LINK_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant CORRECT_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    function run() external view {
        console.log("=== LINK Token Diagnosis ===");
        console.log("AIOracle address:", AI_ORACLE);
        console.log("Wrong LINK token (used during initialization):", WRONG_LINK_TOKEN);
        console.log("Correct LINK token (Base Sepolia official):", CORRECT_LINK_TOKEN);

        // Check balance with wrong LINK token
        bytes memory wrongTokenData = abi.encodeWithSignature("balanceOf(address)", AI_ORACLE);
        (bool success1, bytes memory result1) = WRONG_LINK_TOKEN.staticcall(wrongTokenData);

        uint256 wrongBalance = 0;
        if (success1 && result1.length >= 32) {
            wrongBalance = abi.decode(result1, (uint256));
        }

        // Check balance with correct LINK token
        bytes memory correctTokenData = abi.encodeWithSignature("balanceOf(address)", AI_ORACLE);
        (bool success2, bytes memory result2) = CORRECT_LINK_TOKEN.staticcall(correctTokenData);

        uint256 correctBalance = 0;
        if (success2 && result2.length >= 32) {
            correctBalance = abi.decode(result2, (uint256));
        }

        console.log("");
        console.log("=== BALANCE RESULTS ===");
        console.log("Balance with wrong LINK token:", wrongBalance);
        console.log("Balance with correct LINK token:", correctBalance);

        if (correctBalance > 0 && wrongBalance == 0) {
            console.log("");
            console.log("*** DIAGNOSIS CONFIRMED ***");
            console.log("Problem: AIOracle was initialized with wrong LINK token address");
            console.log("Solution: Transfer", correctBalance, "LINK tokens from correct to wrong address");
            console.log("         OR redeploy AIOracle with correct LINK token address");
        }

        // Check if we can call setChainlinkToken
        console.log("");
        console.log("=== TESTING LINK TOKEN UPDATE ===");

        // Try to see if setChainlinkToken exists (this will revert but we can catch it)
        bytes memory setTokenData = abi.encodeWithSignature("setChainlinkToken(address)", CORRECT_LINK_TOKEN);
        (bool canUpdate,) = AI_ORACLE.staticcall(setTokenData);

        if (canUpdate) {
            console.log("setChainlinkToken function is available");
        } else {
            console.log("setChainlinkToken function is not available or restricted");
        }
    }
}
