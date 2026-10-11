// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { LSP16UniversalFactory } from "@lukso/lsp-smart-contracts/contracts/LSP16UniversalFactory/LSP16UniversalFactory.sol";

abstract contract UniversalFactoryDeployer is Script {

    bytes32 public constant LSP16_FACTORY_SALT = keccak256("UG_LSP16_UNIVERSAL_FACTORY_V1");

    function deployUniversalFactory() public returns (address) {
        bytes memory creationCode = type(LSP16UniversalFactory).creationCode;
        bytes32 creationCodeHash = keccak256(creationCode);

        address deployer = CREATE2_FACTORY;

        address expectedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            LSP16_FACTORY_SALT,
            creationCodeHash
        )))));

        if (expectedAddress.code.length > 0) {
            console.log("Using existing LSP16UniversalFactory at:", expectedAddress);
            return expectedAddress;
        }

        console.log("Deploying LSP16UniversalFactory with CREATE2...");
        console.log("Expected address:", expectedAddress);

        LSP16UniversalFactory factory = new LSP16UniversalFactory{salt: LSP16_FACTORY_SALT}();
        address deployedAddress = address(factory);

        require(deployedAddress != address(0), "LSP16UniversalFactory deployment failed");
        require(deployedAddress == expectedAddress, "LSP16UniversalFactory address mismatch");

        console.log("LSP16UniversalFactory deployed at:", deployedAddress);
        return deployedAddress;
    }

    function computeFactoryAddress() public view returns (address) {
        bytes memory creationCode = type(LSP16UniversalFactory).creationCode;
        bytes32 creationCodeHash = keccak256(creationCode);
        address deployer = CREATE2_FACTORY;

        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            LSP16_FACTORY_SALT,
            creationCodeHash
        )))));
    }
}

contract DeployUniversalFactory is UniversalFactoryDeployer {
    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address factoryAddress = deployUniversalFactory();

        vm.stopBroadcast();

        console.log("\n=== Universal Factory Deployment Summary ===");
        console.log("LSP16UniversalFactory:", factoryAddress);
        console.log("\nThis address will be the same on all chains when deployed with the same parameters.");
        console.log("Use this factory address in other deployment scripts.");

        return factoryAddress;
    }
}
