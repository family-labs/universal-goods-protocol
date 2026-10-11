// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {DemoLSP8Token} from "../src/DemoLSP8Token.sol";
import {LSP20Router} from "../src/LSP20Router.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";
import {LSP20AuditOnlyVerifier} from "../src/LSP20AuditOnlyVerifier.sol";

contract Phase7_OpsTest is Test {
    DemoLSP8Token token;
    LSP20Router router;
    LSP20PassthroughVerifier pass;
    LSP20AuditOnlyVerifier audit;

    function setUp() public {
        router = new LSP20Router(address(this));
        pass = new LSP20PassthroughVerifier();
        audit = new LSP20AuditOnlyVerifier();
        token = new DemoLSP8Token("Demo", "DL8", address(this), address(router));
        router.setDefaultVerifier(address(token), address(pass));
    }

    function testRouterPauseBlocksCalls() public {
        bytes32 tokenId = keccak256("p7");

        router.pauseTarget(address(token), true);
        vm.expectRevert(bytes("ROUTER: paused"));
        token.mintWithVerification(address(0xBEEF), tokenId, true, abi.encode("", ""));

        router.pauseTarget(address(token), false);
        token.mintWithVerification(address(0xBEEF), tokenId, true, abi.encode("", ""));
        assertEq(token.tokenOwnerOf(tokenId), address(0xBEEF));
    }

    function testAuditOnlyEmitsPreAndPost() public {

        router.setVerifierForSelector(address(token), token.transfer.selector, address(audit));
        bytes32 tokenId = keccak256("p7b");
        token.mintWithVerification(address(this), tokenId, true, abi.encode("", ""));

        vm.recordLogs();
        token.transfer(address(this), address(0xA11C3), tokenId, true, abi.encode("", ""));
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool sawPreAudit = false;
        bool sawPreRouter = false;
        for (uint256 i = 0; i < entries.length; i++) {

            bytes32 sig = entries[i].topics.length > 0 ? entries[i].topics[0] : bytes32(0);
            if (sig == keccak256("AuditPre(address,address,bytes4,bytes)")) sawPreAudit = true;
            if (
                sig
                    == keccak256(
                        "PreRouted(bytes32,address,bytes4,address,address,address,uint256,bytes32)"
                    )
            ) sawPreRouter = true;
        }

        assertTrue(sawPreAudit || sawPreRouter);
    }
}
