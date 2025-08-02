// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckNodeRegistryMethods is Script {
    
    address constant NODE_REGISTRY = 0xF619343016DD4c863D56A8bC8fDC033Dd023E9F7;
    address constant TEST_ADDRESS = 0x7c17f9D9378a2aa5fB98BDc8E3b8aaF3c8eedd71;
    
    function run() external view {
        console.log("=== Checking NodeRegistry Methods ===");
        console.log("NodeRegistry address:", NODE_REGISTRY);
        
        // Check totalNodes
        bytes memory totalNodesData = abi.encodeWithSignature("totalNodes()");
        (bool success1, bytes memory result1) = NODE_REGISTRY.staticcall(totalNodesData);
        if (success1 && result1.length >= 32) {
            uint256 totalNodes = abi.decode(result1, (uint256));
            console.log("Total nodes:", totalNodes);
        } else {
            console.log("totalNodes() failed");
        }
        
        // Check deviceTypeCount for different types
        for (uint8 i = 0; i < 6; i++) {
            bytes memory deviceCountData = abi.encodeWithSignature("deviceTypeCount(uint8)", i);
            (bool success2, bytes memory result2) = NODE_REGISTRY.staticcall(deviceCountData);
            if (success2 && result2.length >= 32) {
                uint256 count = abi.decode(result2, (uint256));
                console.log("Device type", i, "count:", count);
            } else {
                console.log("deviceTypeCount() failed for type", i);
            }
        }
        
        // Try to get node details for test address
        bytes memory nodeDetailsData = abi.encodeWithSignature("getNodeDetails(address)", TEST_ADDRESS);
        (bool success3, bytes memory result3) = NODE_REGISTRY.staticcall(nodeDetailsData);
        if (success3 && result3.length > 0) {
            console.log("getNodeDetails() works for test address");
        } else {
            console.log("getNodeDetails() failed for test address");
        }
        
        // Check if test address is registered
        bytes memory isRegisteredData = abi.encodeWithSignature("nodes(address)", TEST_ADDRESS);
        (bool success4, bytes memory result4) = NODE_REGISTRY.staticcall(isRegisteredData);
        if (success4 && result4.length > 0) {
            console.log("nodes() mapping works for test address");
        } else {
            console.log("nodes() mapping failed for test address");
        }
        
        // Try alternative method names
        bytes memory alternativeData1 = abi.encodeWithSignature("getNodesByType(uint8)", uint8(0));
        (bool altSuccess1,) = NODE_REGISTRY.staticcall(alternativeData1);
        console.log("getNodesByType() exists:", altSuccess1);
        
        bytes memory alternativeData2 = abi.encodeWithSignature("nodesByDeviceType(uint8)", uint8(0));
        (bool altSuccess2,) = NODE_REGISTRY.staticcall(alternativeData2);
        console.log("nodesByDeviceType() exists:", altSuccess2);
    }
}