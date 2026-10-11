// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RealWorldAssetInit} from "../src/RealWorldAssetInit.sol";
import {RealWorldAssetLSP16Factory} from "../src/RealWorldAssetLSP16Factory.sol";
import {DeployUniversalFactory} from "./DeployUniversalFactory.s.sol";

contract DeployRealWorldAssetCreate2Factory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeployUniversalFactory universalFactoryDeployer = new DeployUniversalFactory();
        address universalFactoryAddress = universalFactoryDeployer.deployUniversalFactory();

        RealWorldAssetInit implementation = new RealWorldAssetInit();

        RealWorldAssetLSP16Factory factory =
            new RealWorldAssetLSP16Factory(universalFactoryAddress, address(implementation));
        console.log("RealWorldAssetInit deployed at:", address(implementation));
        console.log("RealWorldAssetLSP16Factory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
