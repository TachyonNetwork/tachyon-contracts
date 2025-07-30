// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

// @title UploadABI
// @notice Script to help upload ABI to Basescan for proxy contracts
contract UploadABI is Script {
    function run() external {
        address proxy = 0x2364b88237866CD8561866980bD2f12a6c14819E;

        console.log("To manually add ABI to Basescan:");
        console.log("\n1. Generate ABI:");
        console.log("   forge inspect TachyonToken abi > TachyonToken.abi.json");

        console.log("\n2. Go to: https://sepolia.basescan.org/address/%s#code", proxy);

        console.log("\n3. Click 'More Options' -> 'Update Token Information'");

        console.log("\n4. Or use direct link:");
        console.log("   https://sepolia.basescan.org/token/%s/update", proxy);

        console.log("\n5. Upload the ABI file and submit");

        console.log("\nAlternatively, wait for Basescan to index the proxy verification (can take up to 30 minutes)");
    }
}
