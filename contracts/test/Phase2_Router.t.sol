// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {DemoLSP8Token} from "../src/DemoLSP8Token.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";
import {LSP20Router} from "../src/LSP20Router.sol";
import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";

contract Phase2_RouterTest is Test {
    DemoLSP8Token token;
    LSP20PassthroughVerifier pass;
    LSP20Router router;

    function setUp() public {
        pass = new LSP20PassthroughVerifier();
        router = new LSP20Router(address(this));
        token = new DemoLSP8Token("Demo", "DL8", address(this), address(router));
        router.setDefaultVerifier(address(token), address(pass));
    }

    function testRouter_DefaultPassthrough() public {
        bytes32 tokenId = keccak256("t2");
        token.mintWithVerification(address(0xBEEF), tokenId, true, abi.encode("", ""));
        assertEq(token.tokenOwnerOf(tokenId), address(0xBEEF));
    }

    function testRouter_PostCallNoop() public {

        bytes32 callHash = keccak256(
            abi.encode(
                address(this),
                address(token),
                address(this),
                uint256(0),
                abi.encodePacked(
                    token.mintWithVerification.selector,
                    abi.encode(address(1), bytes32(0), true, abi.encode("", ""))
                )
            )
        );

        bytes4 sel = router.lsp20VerifyCallResult(callHash, "");
        assertEq(sel, ILSP20.lsp20VerifyCallResult.selector);
    }
}
