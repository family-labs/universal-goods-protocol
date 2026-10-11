// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/LSP20Router.sol";
import "../src/LSP20PassthroughVerifier.sol";
import "../src/ServiceProviderRegistry.sol";

contract RouterAndServiceTest is Test {
    LSP20Router router;
    LSP20PassthroughVerifier pass;
    ServiceProviderRegistry spr;
    address owner = address(this);

    function setUp() public {
        router = new LSP20Router(owner);
        pass = new LSP20PassthroughVerifier();
        spr = new ServiceProviderRegistry(owner);
    }

    function testOwnerSetAndPauseAndVerifiers() public {
        router.setDefaultVerifier(address(this), address(pass));
        assertEq(router.defaultVerifier(address(this)), address(pass));

        bytes4 sel = bytes4(0x11112222);
        bytes memory d = abi.encodePacked(sel, abi.encode(uint256(1)));

        router.setVerifierForSelector(address(this), sel, address(this));
        assertEq(router.verifierForSelector(address(this), sel), address(this));

        vm.expectRevert();
        router.lsp20VerifyCall(address(this), address(this), address(this), 0, d);

        router.pauseTarget(address(this), true);
        assertTrue(router.paused(address(this)));
        vm.expectRevert("ROUTER: paused");
        router.lsp20VerifyCall(address(this), address(this), address(this), 0, d);
    }

    function testServiceProviderRegistry() public {
        spr.setProviderStatus(address(this), address(this), true);
        assertTrue(spr.isActive(address(this), address(this)));
    }
}
