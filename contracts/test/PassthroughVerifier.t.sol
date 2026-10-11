// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

contract PassthroughVerifierTest is Test {
    LSP20PassthroughVerifier v;

    function setUp() public {
        v = new LSP20PassthroughVerifier();
    }

    function testVerifyCallAndResult() public {
        bytes4 p = v.lsp20VerifyCall(address(this), address(this), address(this), 0, hex"1234");

        assertEq(p & 0xFFFFFF00, bytes4(bytes3(v.lsp20VerifyCall.selector)));
        bytes4 r = v.lsp20VerifyCallResult(0x0, bytes(""));
        assertEq(r, v.lsp20VerifyCallResult.selector);
    }
}
