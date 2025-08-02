// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/AIOracle.sol";

contract UpdateAIOracleLinkToken is Script {
    // Base Sepolia addresses
    address constant AI_ORACLE = 0x5B71b4Ee99664bD986d741F617838b5e9988dCD1;
    address constant CORRECT_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Updating AIOracle LINK Token Address ===");
        console.log("AIOracle address:", AI_ORACLE);
        console.log("New LINK token address:", CORRECT_LINK_TOKEN);

        AIOracle aiOracle = AIOracle(AI_ORACLE);

        // The LINK token address is set internally in ChainlinkClient
        // We need to call setChainlinkToken which should be available
        // Let's try to call it directly with low-level call

        bytes memory data = abi.encodeWithSignature("setChainlinkToken(address)", CORRECT_LINK_TOKEN);
        (bool success, bytes memory result) = AI_ORACLE.call(data);

        if (success) {
            console.log("SUCCESS: LINK token address updated");
        } else {
            console.log("INFO: setChainlinkToken not available, contract may need redeployment");

            // Let's check what LINK token the contract is currently using
            try aiOracle.getLinkBalance() returns (uint256 balance) {
                console.log("Current LINK balance (old token):", balance);
            } catch {
                console.log("Could not check LINK balance");
            }
        }

        vm.stopBroadcast();

        console.log("");
        console.log("NOTE: If setChainlinkToken is not available, AIOracle needs to be redeployed");
        console.log("with the correct LINK token address:", CORRECT_LINK_TOKEN);
    }
}
