// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/LSP20StrictPolicyVerifier.sol";
import "../src/AssetRegistry.sol";

contract StrictVerifierTest is Test {
    AssetRegistry reg;
    LSP20StrictPolicyVerifier verifier;
    address owner = address(0xABC0);
    address platform = address(0xF00);

    function setUp() public {
        vm.prank(owner);
        reg = new AssetRegistry(owner, true);
        verifier = new LSP20StrictPolicyVerifier(reg, platform, false);
    }

    function testBadCalldataReverts() public {

        bytes memory shortCalldata = new bytes(2);
        vm.expectRevert();
        verifier.lsp20VerifyCall(address(0), address(this), address(this), 0, shortCalldata);
    }
}
