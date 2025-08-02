// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract AddLinkToAIOracle is Script {
    
    // Base Sepolia addresses
    address constant LINK_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant AI_ORACLE = 0x5B71b4Ee99664bD986d741F617838b5e9988dCD1;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        IERC20 link = IERC20(LINK_TOKEN);
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Adding LINK to AIOracle ===");
        console.log("Deployer address:", deployer);
        console.log("AIOracle address:", AI_ORACLE);
        console.log("LINK token address:", LINK_TOKEN);
        
        // Check deployer's LINK balance
        uint256 deployerBalance = link.balanceOf(deployer);
        console.log("Deployer LINK balance:", deployerBalance);
        
        if (deployerBalance == 0) {
            console.log("ERROR: No LINK tokens in deployer wallet!");
            vm.stopBroadcast();
            return;
        }
        
        // Transfer some LINK to AIOracle (let's send 1 LINK = 1e6 since LINK has 6 decimals on Base Sepolia)
        uint256 linkAmount = 1e6; // 1 LINK
        if (deployerBalance < linkAmount) {
            linkAmount = deployerBalance; // Send all available LINK
        }
        
        console.log("Transferring LINK amount:", linkAmount);
        
        bool success = link.transfer(AI_ORACLE, linkAmount);
        if (success) {
            console.log("SUCCESS: LINK transferred to AIOracle");
        } else {
            console.log("ERROR: LINK transfer failed");
        }
        
        // Check new balances
        uint256 newDeployerBalance = link.balanceOf(deployer);
        uint256 aiOracleBalance = link.balanceOf(AI_ORACLE);
        
        console.log("=== Post-Transfer Balances ===");
        console.log("Deployer LINK balance:", newDeployerBalance);
        console.log("AIOracle LINK balance:", aiOracleBalance);
        
        vm.stopBroadcast();
    }
}