// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { LSP16UniversalFactory } from "@lukso/lsp-smart-contracts/contracts/LSP16UniversalFactory/LSP16UniversalFactory.sol";
import { LSP23LinkedContractsFactory } from "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/LSP23LinkedContractsFactory.sol";
import { UniversalProfileInit } from "@lukso/lsp-smart-contracts/contracts/UniversalProfileInit.sol";
import { LSP6KeyManagerInit } from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManagerInit.sol";
import { LSP1UniversalReceiverDelegateUP } from "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1UniversalReceiverDelegateUP/LSP1UniversalReceiverDelegateUP.sol";
import { UniversalProfileInitPostDeploymentModule } from "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/modules/UniversalProfileInitPostDeploymentModule.sol";
import { DeployUniversalFactory } from "./DeployUniversalFactory.s.sol";

contract DeployRelayerInfrastructure is Script {

    bytes32 public constant LSP23_FACTORY_SALT = keccak256("UG_LSP23_FACTORY_V1");
    bytes32 public constant UP_INIT_SALT = keccak256("UG_UP_INIT_V1");
    bytes32 public constant KM_INIT_SALT = keccak256("UG_KM_INIT_V1");
    bytes32 public constant URD_SALT = keccak256("UG_URD_V1");
    bytes32 public constant POST_DEPLOYMENT_MODULE_SALT = keccak256("UG_POST_DEPLOYMENT_MODULE_V1");

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        LSP16UniversalFactory universalFactory = _getOrDeployUniversalFactory();

        address lsp23FactoryAddress = _deployContract(
            universalFactory,
            type(LSP23LinkedContractsFactory).creationCode,
            LSP23_FACTORY_SALT,
            "LSP23LinkedContractsFactory"
        );

        address upInitAddress = _deployContract(
            universalFactory,
            type(UniversalProfileInit).creationCode,
            UP_INIT_SALT,
            "UniversalProfileInit"
        );

        address kmInitAddress = _deployContract(
            universalFactory,
            type(LSP6KeyManagerInit).creationCode,
            KM_INIT_SALT,
            "LSP6KeyManagerInit"
        );

        address urdUpAddress = _deployContract(
            universalFactory,
            type(LSP1UniversalReceiverDelegateUP).creationCode,
            URD_SALT,
            "LSP1UniversalReceiverDelegateUP"
        );

        address postDeploymentModuleAddress = _deployContract(
            universalFactory,
            type(UniversalProfileInitPostDeploymentModule).creationCode,
            POST_DEPLOYMENT_MODULE_SALT,
            "UniversalProfileInitPostDeploymentModule"
        );

        vm.stopBroadcast();

        console.log("\n=== Relayer Infrastructure Deployment Summary ===");
        console.log("LSP16UniversalFactory", address(universalFactory));
        console.log("LSP23LinkedContractsFactory:", lsp23FactoryAddress);
        console.log("UniversalProfileInit:", upInitAddress);
        console.log("LSP6KeyManagerInit:", kmInitAddress);
        console.log("LSP1UniversalReceiverDelegateUP:", urdUpAddress);
        console.log("UniversalProfileInitPostDeploymentModule:", postDeploymentModuleAddress);
    }

    function _getOrDeployUniversalFactory() internal returns (LSP16UniversalFactory) {
        DeployUniversalFactory factoryDeployer = new DeployUniversalFactory();
        address expectedAddress = factoryDeployer.computeFactoryAddress();
        address factoryAddress = factoryDeployer.deployUniversalFactory();

        console.log("Expected LSP16UniversalFactory address:", expectedAddress);
        console.log("Using LSP16UniversalFactory address:", factoryAddress);
        if (factoryAddress != expectedAddress) {
            console.log("Warning: factory address differs from expected CREATE2 address");
        }

        return LSP16UniversalFactory(factoryAddress);
    }

    function _deployContract(
        LSP16UniversalFactory factory,
        bytes memory creationCode,
        bytes32 salt,
        string memory contractName
    ) internal returns (address) {

        bytes32 creationCodeHash = keccak256(creationCode);
        address expectedAddress = factory.computeAddress(creationCodeHash, salt, false, "");

        if (expectedAddress.code.length > 0) {
            console.log(contractName, "already deployed at:", expectedAddress);
            return expectedAddress;
        }

        console.log("Deploying", contractName, "...");
        address deployedAddress = factory.deployCreate2(creationCode, salt);
        console.log(contractName, "deployed at:", deployedAddress);

        require(deployedAddress == expectedAddress, "Address mismatch");

        return deployedAddress;
    }
}
