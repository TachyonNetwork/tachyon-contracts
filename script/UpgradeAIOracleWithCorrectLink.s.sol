// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IAIOracle {
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
    function initialize(address _link, address _oracle, bytes32 _jobId, uint256 _fee, address initialOwner) external;
    function owner() external view returns (address);
    function getLinkBalance() external view returns (uint256);
}

contract UpgradeAIOracleWithCorrectLink is Script {
    
    // Base Sepolia addresses
    address constant AI_ORACLE_PROXY = 0x5B71b4Ee99664bD986d741F617838b5e9988dCD1;
    address constant CORRECT_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address constant WRONG_LINK_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Checking LINK Token Issue ===");
        console.log("AIOracle proxy:", AI_ORACLE_PROXY);
        console.log("Wrong LINK token:", WRONG_LINK_TOKEN);
        console.log("Correct LINK token:", CORRECT_LINK_TOKEN);
        
        // Check balance with wrong LINK token
        bytes memory wrongTokenData = abi.encodeWithSignature("balanceOf(address)", AI_ORACLE_PROXY);
        (bool success1, bytes memory result1) = WRONG_LINK_TOKEN.staticcall(wrongTokenData);
        if (success1 && result1.length >= 32) {
            uint256 wrongBalance = abi.decode(result1, (uint256));
            console.log("Balance with wrong LINK token:", wrongBalance);
        }
        
        // Check balance with correct LINK token
        bytes memory correctTokenData = abi.encodeWithSignature("balanceOf(address)", AI_ORACLE_PROXY);
        (bool success2, bytes memory result2) = CORRECT_LINK_TOKEN.staticcall(correctTokenData);
        if (success2 && result2.length >= 32) {
            uint256 correctBalance = abi.decode(result2, (uint256));
            console.log("Balance with correct LINK token:", correctBalance);
            
            if (correctBalance > 0) {
                console.log("CONFIRMED: AIOracle has", correctBalance, "LINK tokens at correct address");
                console.log("The issue is that AIOracle contract was initialized with wrong LINK token address");
                console.log("Job creation fails because it checks balance using wrong LINK token");
                
                // The solution is to either:
                // 1. Transfer LINK to the wrong token address, or  
                // 2. Redeploy AIOracle with correct LINK token address
                
                console.log("");
                console.log("=== SOLUTION OPTIONS ===");
                console.log("Option 1: Transfer LINK from", CORRECT_LINK_TOKEN, "to", WRONG_LINK_TOKEN);
                console.log("Option 2: Redeploy AIOracle contract with correct LINK token address");
                console.log("Option 3: Try to update LINK token address if contract allows it");
                
                // Let's check if we can call setChainlinkToken
                bytes memory setTokenData = abi.encodeWithSignature("setChainlinkToken(address)", CORRECT_LINK_TOKEN);
                (bool canUpdate, ) = AI_ORACLE_PROXY.call(setTokenData);
                
                if (canUpdate) {
                    console.log("SUCCESS: Updated LINK token address to correct one");
                } else {
                    console.log("Cannot update LINK token address - function not available");
                }
            }
        }
        
        vm.stopBroadcast();
    }
}