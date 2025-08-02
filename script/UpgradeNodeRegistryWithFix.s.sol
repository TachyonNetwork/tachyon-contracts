// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/NodeRegistryCompactWithFix.sol";

contract UpgradeNodeRegistryWithFix is Script {
    address constant NODE_REGISTRY_PROXY = 0xF619343016DD4c863D56A8bC8fDC033Dd023E9F7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Upgrading NodeRegistry with Compatibility Fix ===");
        console.log("Deployer:", deployer);
        console.log("NodeRegistry proxy:", NODE_REGISTRY_PROXY);

        // Deploy new implementation
        console.log("Deploying NodeRegistryCompactWithFix implementation...");
        NodeRegistryCompactWithFix newImplementation = new NodeRegistryCompactWithFix();
        console.log("New implementation deployed at:", address(newImplementation));

        // Get proxy instance
        NodeRegistryCompact registryProxy = NodeRegistryCompact(NODE_REGISTRY_PROXY);

        // Upgrade to new implementation
        console.log("Upgrading proxy to new implementation...");
        registryProxy.upgradeToAndCall(address(newImplementation), "");

        console.log("SUCCESS: NodeRegistry upgraded with JobManager compatibility!");
        console.log("");
        console.log("The new implementation includes:");
        console.log("- getNodeDetails() function for JobManager compatibility");
        console.log("- totalActiveNodes() function");
        console.log("");
        console.log("JobManager should now work without modifications!");

        vm.stopBroadcast();
    }
}
