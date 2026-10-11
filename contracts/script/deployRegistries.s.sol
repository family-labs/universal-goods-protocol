// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";

contract DeployRegistries is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ServiceProviderRegistry svc = new ServiceProviderRegistry(msg.sender);
        AssetRegistryV2 ar = new AssetRegistryV2(msg.sender);

        console.log("ServiceProviderRegistry deployed at %s", address(svc));
        console.log("AssetRegistryV2 deployed at %s", address(ar));

        vm.stopBroadcast();
    }
}
