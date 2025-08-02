// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckActiveNodes is Script {
    
    address constant NODE_REGISTRY = 0xF619343016DD4c863D56A8bC8fDC033Dd023E9F7;
    
    function run() external view {
        console.log("=== Checking Active Nodes ===");
        console.log("NodeRegistry address:", NODE_REGISTRY);
        
        // Check total active nodes
        bytes memory activeNodesData = abi.encodeWithSignature("totalActiveNodes()");
        (bool success1, bytes memory result1) = NODE_REGISTRY.staticcall(activeNodesData);
        if (success1 && result1.length >= 32) {
            uint256 totalActive = abi.decode(result1, (uint256));
            console.log("Total active nodes:", totalActive);
            
            if (totalActive == 0) {
                console.log("ERROR: No active nodes in the network!");
                console.log("Jobs cannot be created without active nodes");
                console.log("Please register at least one node first");
            }
        }
        
        // Check total registered nodes
        bytes memory totalNodesData = abi.encodeWithSignature("totalNodes()");
        (bool success2, bytes memory result2) = NODE_REGISTRY.staticcall(totalNodesData);
        if (success2 && result2.length >= 32) {
            uint256 totalNodes = abi.decode(result2, (uint256));
            console.log("Total registered nodes:", totalNodes);
        }
    }
}