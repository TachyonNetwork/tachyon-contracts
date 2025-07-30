// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

// @title VerifyProxy
// @notice Script to properly verify proxy contracts on Etherscan
// @dev This helps Etherscan recognize the proxy pattern and show the correct UI
contract VerifyProxy is Script {
    function run() external {
        // Proxy address from latest deployment
        address proxy = 0x2364b88237866CD8561866980bD2f12a6c14819E;
        address implementation = 0xd8ac1a18FD6Fa7f0b369C50c4484cc9360A9D1B4;

        console.log("Verifying proxy contract at:", proxy);
        console.log("Implementation at:", implementation);

        // The proxy is already verified, but we need to mark it as proxy
        // This is done through Etherscan's "Proxy Contract Verification" feature
        console.log("\nTo complete proxy verification:");
        console.log("1. Go to https://sepolia.basescan.org/address/%s#code", proxy);
        console.log("2. Click 'Is this a proxy?' button");
        console.log("3. Select 'Transparent/Upgradeable Proxy'");
        console.log("4. Verify and it will automatically detect the implementation");

        console.log("\nAlternatively, use Etherscan API:");
        console.log("curl -X POST https://api-sepolia.basescan.org/api \\");
        console.log("  -d 'module=contract' \\");
        console.log("  -d 'action=verifyproxycontract' \\");
        console.log("  -d 'address=%s' \\", proxy);
        console.log("  -d 'expectedimplementation=%s' \\", implementation);
        console.log("  -d 'apikey=$ETHERSCAN_API_KEY'");
    }
}
