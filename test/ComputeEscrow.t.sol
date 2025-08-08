// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/ComputeEscrow.sol";
import "./mocks/MockERC20.sol";

contract ComputeEscrowTest is Test {
    ComputeEscrow public escrow;
    MockERC20 public usdc;
    address public owner = address(0xA11CE);
    address public jobManager = address(0xBEEF);
    address public payer = address(0xCAFE);
    address public provider = address(0xF00D);

    function setUp() public {
        // mock USDC with 6 decimals
        usdc = new MockERC20("MockUSDC", "mUSDC", 6);
        ComputeEscrow impl = new ComputeEscrow();
        bytes memory initData = abi.encodeWithSelector(ComputeEscrow.initialize.selector, address(usdc), owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        escrow = ComputeEscrow(address(proxy));

        vm.startPrank(owner);
        escrow.grantRole(escrow.JOB_MANAGER_ROLE(), jobManager);
        vm.stopPrank();

        // fund payer
        usdc.mint(payer, 1_000_000_000); // 1000 mUSDC (6 decimals)
    }

    function testCreateFundRelease() public {
        vm.prank(jobManager);
        escrow.createEscrow(1, payer, 500_000); // 0.5

        vm.startPrank(payer);
        usdc.approve(address(escrow), 500_000);
        escrow.fundEscrow(1);
        vm.stopPrank();

        vm.prank(jobManager);
        escrow.setPayee(1, provider);

        uint256 balBefore = usdc.balanceOf(provider);
        vm.prank(jobManager);
        escrow.release(1, address(0));
        uint256 balAfter = usdc.balanceOf(provider);
        assertEq(balAfter - balBefore, 500_000);
    }

    function testRefund() public {
        vm.prank(jobManager);
        escrow.createEscrow(2, payer, 123_456);
        vm.startPrank(payer);
        usdc.approve(address(escrow), 123_456);
        escrow.fundEscrow(2);
        vm.stopPrank();

        uint256 payerBefore = usdc.balanceOf(payer);
        vm.prank(jobManager);
        escrow.refund(2);
        uint256 payerAfter = usdc.balanceOf(payer);
        assertEq(payerAfter, payerBefore + 123_456);
    }
}
