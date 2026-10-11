// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";

contract ServiceProviderRegistryExtraTest is Test {
    ServiceProviderRegistry reg;
    address owner = address(this);

    function setUp() public {
        reg = new ServiceProviderRegistry(owner);
    }

    function testSetProviderStatusRevertNotOwner() public {
        vm.prank(address(0xAB));
        vm.expectRevert(bytes("OWNABLE: not owner"));
        reg.setProviderStatus(address(0x1), address(0x2), true);
    }

    function testChangeOwnerAndUseNewOwner() public {
        reg.setProviderStatus(address(0x1), address(0x2), true);

        reg.setOwner(address(0xB0));

        vm.expectRevert(bytes("OWNABLE: not owner"));
        reg.setProviderStatus(address(0x1), address(0x3), true);

        vm.prank(address(0xB0));
        reg.setProviderStatus(address(0x1), address(0x3), true);
    }
}
