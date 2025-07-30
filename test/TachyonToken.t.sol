// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/TachyonToken.sol";

// @title TachyonTokenTest
// @notice Tests for TachyonToken contract on Base Sepolia.
// @dev Uses payable cast for proxy address to handle payable fallback/receive.
contract TachyonTokenTest is Test {
    TachyonToken token;
    address owner = 0x7c17f9D9378a2aa5fB98BDc8E3b8aaF3c8eedd71;
    address user = address(0x123);

    function setUp() public {
        token = TachyonToken(payable(0xc21040e6AD80578cAE6BdaA03e968Fbb60A4E284));
    }

    function testName() public {
        assertEq(token.name(), "Tachyon Token");
    }

    function testOwner() public {
        assertEq(token.owner(), owner);
    }

    function testMint() public {
        vm.prank(owner);
        token.mint(user, 1000 * 10**18);
        assertEq(token.balanceOf(user), 1000 * 10**18);
    }
}