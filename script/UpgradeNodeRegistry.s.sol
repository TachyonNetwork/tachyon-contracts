// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/NodeRegistryCompact.sol";

contract UpgradeNodeRegistry is Script {
    
    address constant NODE_REGISTRY_PROXY = 0xF619343016DD4c863D56A8bC8fDC033Dd023E9F7;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Upgrading NodeRegistry ===");
        console.log("NodeRegistry proxy:", NODE_REGISTRY_PROXY);
        
        // Deploy new implementation
        NodeRegistryCompact newImplementation = new NodeRegistryCompact();
        console.log("New implementation:", address(newImplementation));
        
        // Upgrade
        NodeRegistryCompact(NODE_REGISTRY_PROXY).upgradeToAndCall(address(newImplementation), "");
        
        console.log("SUCCESS: NodeRegistry upgraded with getNodeDetails function!");
        
        vm.stopBroadcast();
    }
}