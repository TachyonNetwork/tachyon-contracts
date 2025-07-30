// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

// @title ForceProxyVerification
// @notice Alternative approach to verify proxy on Basescan
contract ForceProxyVerification is Script {
    function run() external {
        console.log("=== Manual Proxy Verification Steps ===\n");

        console.log("Since automatic verification is having issues, follow these steps:\n");

        console.log("1. First, verify the proxy pattern manually:");
        console.log("   Go to: https://sepolia.basescan.org/proxycontractchecker");
        console.log("   Enter proxy address: 0x2364b88237866CD8561866980bD2f12a6c14819E");
        console.log("   Click 'Verify'");

        console.log("\n2. If that doesn't work, use the 'Update Token Info' approach:");
        console.log("   Go to: https://sepolia.basescan.org/address/0x2364b88237866CD8561866980bD2f12a6c14819E");
        console.log("   Click 'More Options' -> 'Is this a proxy?'");
        console.log("   Select 'Custom' and enter:");
        console.log("   - Implementation: 0xd8ac1a18FD6Fa7f0b369C50c4484cc9360A9D1B4");
        console.log("   - Storage slot: 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");
        console.log("   (This is the standard EIP-1967 implementation slot)");

        console.log("\n3. Alternative - Direct interaction:");
        console.log("   You can interact with the contract directly using:");
        console.log("   - Implementation address: 0xd8ac1a18FD6Fa7f0b369C50c4484cc9360A9D1B4");
        console.log("   - Use that address in Basescan to read/write");

        console.log("\n4. For development, you can use cast commands:");
        console.log(
            "   cast call 0x2364b88237866CD8561866980bD2f12a6c14819E 'name()' --rpc-url https://sepolia.base.org"
        );
        console.log(
            "   cast call 0x2364b88237866CD8561866980bD2f12a6c14819E 'owner()' --rpc-url https://sepolia.base.org"
        );
    }
}
