// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TachyonToken.sol";

// @title TachyonTokenTest
// @notice Tests for TachyonToken contract.
contract TachyonTokenTest is Test {
    TachyonToken token;
    address owner = makeAddr("owner");
    address user = address(0x123);

    function setUp() public {
        // Deploy implementation
        TachyonToken implementation = new TachyonToken();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(TachyonToken.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to TachyonToken interface
        token = TachyonToken(payable(address(proxy)));
    }

    function testName() public {
        assertEq(token.name(), "Tachyon Token");
    }

    function testOwner() public {
        assertEq(token.owner(), owner);
    }

    function testMint() public {
        vm.prank(owner);
        token.mint(user, 1000 * 10 ** 18);
        assertEq(token.balanceOf(user), 1000 * 10 ** 18);
    }
}
