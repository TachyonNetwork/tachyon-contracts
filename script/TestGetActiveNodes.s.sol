// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract TestGetActiveNodes is Script {
    
    address constant NODE_REGISTRY = 0xF619343016DD4c863D56A8bC8fDC033Dd023E9F7;
    
    function run() external view {
        console.log("=== Testing getActiveNodes() ===");
        console.log("NodeRegistry address:", NODE_REGISTRY);
        
        // Call getActiveNodes()
        bytes memory getActiveNodesData = abi.encodeWithSignature("getActiveNodes()");
        (bool success, bytes memory result) = NODE_REGISTRY.staticcall(getActiveNodesData);
        
        if (success && result.length > 0) {
            address[] memory activeNodes = abi.decode(result, (address[]));
            console.log("SUCCESS: getActiveNodes() returned", activeNodes.length, "nodes");
            
            for (uint256 i = 0; i < activeNodes.length && i < 5; i++) {
                console.log("Active node", i + 1, ":", activeNodes[i]);
                
                // Get details for each node
                bytes memory detailsData = abi.encodeWithSignature("getNodeDetails(address)", activeNodes[i]);
                (bool detailsSuccess, bytes memory detailsResult) = NODE_REGISTRY.staticcall(detailsData);
                
                if (detailsSuccess && detailsResult.length > 0) {
                    console.log("  Node details available: YES");
                } else {
                    console.log("  Node details available: NO");
                }
            }
        } else {
            console.log("ERROR: getActiveNodes() failed");
            console.log("Success:", success);
            console.log("Result length:", result.length);
        }
    }
}