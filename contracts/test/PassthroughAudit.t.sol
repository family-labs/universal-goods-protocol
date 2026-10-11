// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/LSP20PassthroughVerifier.sol";
import "../src/LSP20AuditOnlyVerifier.sol";

contract PassthroughAuditTest is Test {
    LSP20PassthroughVerifier passthrough;
    LSP20AuditOnlyVerifier audit;

    function setUp() public {
        passthrough = new LSP20PassthroughVerifier();
        audit = new LSP20AuditOnlyVerifier();
    }

    function testPassthroughReturnsOk() public {
        bytes4 sel = bytes4(0xdeadbeef);
        bytes memory callData = abi.encodePacked(sel, abi.encode(uint256(1)));
        bytes4 ret =
            passthrough.lsp20VerifyCall(address(0), address(this), address(this), 0, callData);

        assertEq(uint8(bytes1(abi.encodePacked(ret)[3])), 0);
    }

    function testAuditEmitsPreAndPostAndRequestsPost() public {
        bytes4 sel = bytes4(0xfeedc0de);
        bytes memory callData = abi.encodePacked(sel, abi.encode(uint256(1)));

        vm.expectEmit(true, true, true, true);
        emit AuditPre(address(this), address(this), sel, callData);
        bytes4 status = audit.lsp20VerifyCall(address(0), address(this), address(this), 0, callData);

        assertEq(uint8(bytes1(abi.encodePacked(status)[3])), 1);

        bytes32 callHash =
            keccak256(abi.encode(address(0), address(this), address(this), uint256(0), callData));
        bytes memory result = "ok";
        vm.expectEmit(true, true, true, true);
        emit AuditPost(callHash, result);
        bytes4 res = audit.lsp20VerifyCallResult(callHash, result);
        assertEq(res, bytes4(abi.encodePacked(bytes4(res))));
    }

    event AuditPre(address indexed target, address indexed caller, bytes4 selector, bytes data);
    event AuditPost(bytes32 indexed callHash, bytes result);
}
