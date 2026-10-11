// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/LSP20Verifier.sol";
import "../src/DemoLSP8Token.sol";

contract VerifierMinimalTest is Test {
    LSP20Verifier verifier;
    DemoLSP8Token token;
    address signerPk = address(0x1234);

    function setUp() public {

        verifier = new LSP20Verifier(address(0xBEEF));
        token = new DemoLSP8Token("n", "s", address(this), address(verifier));
    }

    function testRevertOnZeroTarget() public {
        bytes memory callData = new bytes(4);
        vm.expectRevert("LSP20: target zero-address");
        verifier.lsp20VerifyCall(address(0), address(0), address(this), 0, callData);
    }

    function testRevertOnShortCalldata() public {
        bytes memory callData = new bytes(2);
        vm.expectRevert("LSP20: invalid calldata");
        verifier.lsp20VerifyCall(address(0), address(this), address(this), 0, callData);
    }
}
