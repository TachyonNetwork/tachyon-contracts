// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/TachyonToken.sol";

// @title TransferOwnership
// @notice Transfers ownership and TACH tokens to a new owner on Base Sepolia.
// @dev Uses payable cast to handle TachyonToken's payable fallback/receive functions.
contract TransferOwnership is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TachyonToken token = TachyonToken(payable(0x4c074046b03bbfb9e116018440a7D46861d0E9af));
        address newOwner = 0x7c17f9D9378a2aa5fB98BDc8E3b8aaF3c8eedd71;

        // Transfer ownership
        token.transferOwnership(newOwner);

        // Transfer tokens
        uint256 balance = token.balanceOf(msg.sender);
        token.transfer(newOwner, balance);

        console.log("Ownership transferred to:", newOwner);
        console.log("Tokens transferred:", balance);

        vm.stopBroadcast();
    }
}
