// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/AIOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployFixedAIOracle is Script {
    // Base Sepolia addresses
    address constant CORRECT_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address constant OLD_AI_ORACLE = 0xFa62d464be301ed9378312fc34d82B2121311fE8;

    // Chainlink oracle configuration (using Base Sepolia test values)
    address constant ORACLE = 0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD; // Base Sepolia oracle
    bytes32 constant JOB_ID = 0x7da2702f37fd48e5b1b9a5715e3509b6cc2b9c4b4b9a7a6d7d4c8b8c8b8c8b8c; // Example job ID
    uint256 constant FEE = 0.1 * 10 ** 18; // 0.1 LINK

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying New AIOracle with Correct LINK Token ===");
        console.log("Deployer address:", deployer);
        console.log("Old AIOracle address:", OLD_AI_ORACLE);
        console.log("Correct LINK token:", CORRECT_LINK_TOKEN);
        console.log("Oracle address:", ORACLE);

        // Deploy new AIOracle implementation
        console.log("Deploying new AIOracle implementation...");
        AIOracle implementation = new AIOracle();
        console.log("New AIOracle implementation deployed at:", address(implementation));

        // Prepare initialization data
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

        // Deploy proxy
        console.log("Deploying new proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("New AIOracle proxy deployed at:", address(proxy));

        console.log("");
        console.log("=== SUCCESS! ===");
        console.log("New AIOracle deployed with correct LINK token!");
        console.log("Proxy address:", address(proxy));
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Update deployments.json with new AIOracle address:", address(proxy));
        console.log("2. Update backend configuration to use new AIOracle address");
        console.log("3. Send LINK tokens to new AIOracle address:", address(proxy));
        console.log("4. Test job creation");

        vm.stopBroadcast();
    }
}
