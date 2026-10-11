// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {MockStablecoin} from "../src/MockStablecoin.sol";
import {DataLinkedEscrow} from "../src/DataLinkedEscrow.sol";

contract DataLinkedEscrowTest is Test {
    MockStablecoin token;
    DataLinkedEscrow escrow;

    address depositor = address(0xA11CE);
    address payee = address(0xB0B);

    bytes32 payloadHash = keccak256("invoice-data-credential");
    uint256 amount = 1000e18;

    function setUp() public {
        token = new MockStablecoin(address(this));
        escrow = new DataLinkedEscrow();

        token.mint(depositor, amount);

        vm.prank(depositor);
        token.authorizeOperator(address(escrow), amount, "");
    }

    function testDepositAndSettle() public {

        vm.prank(depositor);
        escrow.deposit(address(token), amount, payee, payloadHash);

        (
            address d,
            address p,
            address t,
            uint256 a,
            bool settled
        ) = escrow.escrows(payloadHash);
        assertEq(d, depositor);
        assertEq(p, payee);
        assertEq(t, address(token));
        assertEq(a, amount);
        assertFalse(settled);

        assertEq(token.balanceOf(depositor), 0);
        assertEq(token.balanceOf(address(escrow)), amount);

        vm.prank(depositor);
        escrow.settle(payloadHash);

        assertEq(token.balanceOf(payee), amount);
        assertEq(token.balanceOf(address(escrow)), 0);

        (,,,, bool isSettled) = escrow.escrows(payloadHash);
        assertTrue(isSettled);
    }

    function testDoubleDepositReverts() public {
        vm.prank(depositor);
        escrow.deposit(address(token), amount, payee, payloadHash);

        token.mint(depositor, amount);
        vm.prank(depositor);
        token.authorizeOperator(address(escrow), amount, "");

        vm.expectRevert(DataLinkedEscrow.EscrowAlreadyExists.selector);
        vm.prank(depositor);
        escrow.deposit(address(token), amount, payee, payloadHash);
    }

    function testDoubleSettleReverts() public {
        vm.prank(depositor);
        escrow.deposit(address(token), amount, payee, payloadHash);

        vm.prank(depositor);
        escrow.settle(payloadHash);

        vm.expectRevert(DataLinkedEscrow.EscrowAlreadySettled.selector);
        vm.prank(depositor);
        escrow.settle(payloadHash);
    }

    function testNonDepositorSettleReverts() public {
        vm.prank(depositor);
        escrow.deposit(address(token), amount, payee, payloadHash);

        vm.expectRevert(DataLinkedEscrow.OnlyDepositor.selector);
        vm.prank(payee);
        escrow.settle(payloadHash);
    }

    function testSettleNonexistentReverts() public {
        bytes32 fakeHash = keccak256("nonexistent");

        vm.expectRevert(DataLinkedEscrow.EscrowNotFound.selector);
        escrow.settle(fakeHash);
    }
}
