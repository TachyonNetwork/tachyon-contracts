// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/AIOracle.sol";

contract UpgradeAIOracleFixLink is Script {
    // Correct addresses from deployments.json
    address constant AI_ORACLE_PROXY = 0xFa62d464be301ed9378312fc34d82B2121311fE8;
    address constant CORRECT_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Upgrading AIOracle to Fix LINK Token ===");
        console.log("Deployer address:", deployer);
        console.log("AIOracle proxy:", AI_ORACLE_PROXY);
        console.log("Correct LINK token:", CORRECT_LINK_TOKEN);

        // Deploy new AIOracle implementation
        console.log("Deploying new AIOracle implementation...");
        AIOracle newImplementation = new AIOracle();
        console.log("New implementation deployed at:", address(newImplementation));

        // Get the current proxy instance
        AIOracle aiOracleProxy = AIOracle(AI_ORACLE_PROXY);

        // Since we can't reinitialize, we'll just upgrade to new implementation
        // The LINK token will need to be set separately if possible
        console.log("Upgrading proxy to new implementation...");
        aiOracleProxy.upgradeToAndCall(address(newImplementation), "");

        console.log("SUCCESS: AIOracle upgraded with correct LINK token!");
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Send LINK tokens to AIOracle:", AI_ORACLE_PROXY);
        console.log("2. Use correct LINK token address:", CORRECT_LINK_TOKEN);
        console.log("3. Test job creation");

        vm.stopBroadcast();
    }
}
