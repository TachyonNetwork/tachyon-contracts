// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/ZKTaskVerifier.sol";

// @title DeployZKVerifier
// @notice Deployment script for ZK verifier
// @dev Deploys the ZK verifier separately for integration with existing system
contract DeployZKVerifier is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying ZK Verifier ===");
        console.log("Deployer:", deployer);

        // Deploy ZKTaskVerifier implementation
        ZKTaskVerifier zkImpl = new ZKTaskVerifier();
        console.log("ZK Verifier Implementation:", address(zkImpl));

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(ZKTaskVerifier.initialize.selector, deployer);

        ERC1967Proxy zkProxy = new ERC1967Proxy(address(zkImpl), initData);
        console.log("ZK Verifier Proxy:", address(zkProxy));

        // Verify initialization
        ZKTaskVerifier zkVerifier = ZKTaskVerifier(address(zkProxy));
        require(zkVerifier.isInitialized(), "ZK verifier not initialized");
        console.log("Verification Key Hash:", vm.toString(zkVerifier.getVerificationKeyHash()));

        // Save deployment info
        string memory json = string.concat(
            "{\n",
            '  "network": "base-sepolia",\n',
            '  "timestamp": "',
            vm.toString(block.timestamp),
            '",\n',
            '  "zkVerifier": {\n',
            '    "proxy": "',
            vm.toString(address(zkProxy)),
            '",\n',
            '    "implementation": "',
            vm.toString(address(zkImpl)),
            '",\n',
            '    "verificationKeyHash": "',
            vm.toString(zkVerifier.getVerificationKeyHash()),
            '"\n',
            "  }\n",
            "}"
        );

        vm.writeFile("zkverifier-deployment.json", json);
        console.log("Deployment info saved to zkverifier-deployment.json");

        vm.stopBroadcast();
    }
}
