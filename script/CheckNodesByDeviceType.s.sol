// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckNodesByDeviceType is Script {
    address constant NODE_REGISTRY = 0xF619343016DD4c863D56A8bC8fDC033Dd023E9F7;

    function run() external view {
        console.log("=== Checking Nodes by Device Type ===");
        console.log("NodeRegistry address:", NODE_REGISTRY);

        string[6] memory deviceNames = ["Desktop", "Laptop", "Mobile", "Server", "IoT Device", "GPU Rig"];

        for (uint8 i = 0; i < 6; i++) {
            console.log("");
            console.log("Device Type", i, ":", deviceNames[i]);

            // Get nodes by device type
            bytes memory nodesByTypeData = abi.encodeWithSignature("getNodesByDeviceType(uint8)", i);
            (bool success, bytes memory result) = NODE_REGISTRY.staticcall(nodesByTypeData);

            if (success) {
                address[] memory nodes = abi.decode(result, (address[]));
                console.log("  Found", nodes.length, "nodes");

                for (uint256 j = 0; j < nodes.length && j < 3; j++) {
                    console.log("  Node", j + 1, ":", nodes[j]);

                    // Get node details
                    bytes memory nodeDetailsData = abi.encodeWithSignature("getNodeDetails(address)", nodes[j]);
                    (bool detailsSuccess, bytes memory detailsResult) = NODE_REGISTRY.staticcall(nodeDetailsData);

                    if (detailsSuccess && detailsResult.length > 0) {
                        console.log("    Has details: true");
                    } else {
                        console.log("    Has details: false");
                    }
                }
            } else {
                console.log("  ERROR: Failed to get nodes for device type", i);
            }
        }

        // Check total nodes
        bytes memory totalNodesData = abi.encodeWithSignature("totalNodes()");
        (bool totalSuccess, bytes memory totalResult) = NODE_REGISTRY.staticcall(totalNodesData);
        if (totalSuccess && totalResult.length >= 32) {
            uint256 totalNodes = abi.decode(totalResult, (uint256));
            console.log("");
            console.log("Total nodes in registry:", totalNodes);
        }
    }
}
