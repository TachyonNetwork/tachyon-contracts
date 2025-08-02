// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/AIOracle.sol";

contract RedeployAIOracle is Script {
    
    // Base Sepolia addresses
    address constant CORRECT_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address constant OLD_AI_ORACLE = 0x5B71b4Ee99664bD986d741F617838b5e9988dCD1;
    
    // Chainlink oracle configuration (using Base Sepolia test values)
    address constant ORACLE = 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD; // Base Sepolia oracle
    bytes32 constant JOB_ID = 0x7da2702f37fd48e5b1b9a5715e3509b6cc2b9c4b4b9a7a6d7d4c8b8c8b8c8b8c; // Example job ID
    uint256 constant FEE = 0.1 * 10**18; // 0.1 LINK
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Redeploying AIOracle with Correct LINK Token ===");
        console.log("Deployer address:", deployer);
        console.log("Old AIOracle address:", OLD_AI_ORACLE);
        console.log("Correct LINK token:", CORRECT_LINK_TOKEN);
        console.log("Oracle address:", ORACLE);
        
        // Deploy new AIOracle implementation
        console.log("Deploying new AIOracle implementation...");
        AIOracle newImplementation = new AIOracle();
        console.log("New AIOracle implementation deployed at:", address(newImplementation));
        
        // Deploy new proxy using OpenZeppelin's ERC1967Proxy
        bytes memory initData = abi.encodeCall(
            AIOracle.initialize,
            (
                CORRECT_LINK_TOKEN,
                ORACLE,
                JOB_ID,
                FEE,
                deployer // owner
            )
        );
        
        // Deploy minimal proxy manually
        bytes memory proxyBytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            address(newImplementation),
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        
        address newProxy;
        assembly {
            newProxy := create2(0, add(proxyBytecode, 0x20), mload(proxyBytecode), salt)
        }
        
        // Initialize the new proxy
        (bool success, ) = newProxy.call(initData);
        require(success, "Initialization failed");
        
        console.log("New AIOracle proxy deployed at:", newProxy);
        console.log("");
        console.log("=== UPDATE REQUIRED ===");
        console.log("Update deployments.json with new AIOracle address:", newProxy);
        console.log("Update backend configuration to use new AIOracle address");
        console.log("Send LINK tokens to new AIOracle address:", newProxy);
        
        vm.stopBroadcast();
    }
}