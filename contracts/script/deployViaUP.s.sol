// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";

contract DeployViaUP is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address up = vm.envAddress("UNIVERSAL_PROFILE");

        require(up != address(0), "UNIVERSAL_PROFILE env must be set");

        vm.startBroadcast(deployerPrivateKey);

        UniversalProfile profile = UniversalProfile(payable(up));

        bytes memory svcInit =
            abi.encodePacked(type(ServiceProviderRegistry).creationCode, abi.encode(up));

        profile.execute(1, address(0), 0, svcInit);
        console.log("Called UniversalProfile.execute to create ServiceProviderRegistry (owner=UP)");

        bytes memory arInit = abi.encodePacked(type(AssetRegistry).creationCode, abi.encode(up));
        profile.execute(1, address(0), 0, arInit);
        console.log("Called UniversalProfile.execute to create AssetRegistry (owner=UP)");

        vm.stopBroadcast();
    }
}
