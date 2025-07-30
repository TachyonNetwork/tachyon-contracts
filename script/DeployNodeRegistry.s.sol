// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/NodeRegistry.sol";

contract DeployNodeRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the actual deployer address
        address deployer = vm.addr(deployerPrivateKey);

        address tachyonToken = 0x4c074046b03bbfb9e116018440a7D46861d0E9af; // Proxy address
        address initialOwner = deployer; // Use actual deployer address
        NodeRegistry nodeRegistry = new NodeRegistry();
        console.log("NodeRegistry deployed at:", address(nodeRegistry));

        vm.stopBroadcast();
    }
}
