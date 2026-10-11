// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { LSP16UniversalFactory } from "@lukso/lsp-smart-contracts/contracts/LSP16UniversalFactory/LSP16UniversalFactory.sol";
import { LSP23LinkedContractsFactory } from
    "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/LSP23LinkedContractsFactory.sol";
import { UniversalProfileInitPostDeploymentModule } from
    "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/modules/UniversalProfileInitPostDeploymentModule.sol";
import { UniversalProfileInit } from "@lukso/lsp-smart-contracts/contracts/UniversalProfileInit.sol";
import { LSP6KeyManagerInit } from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManagerInit.sol";
import { LSP1UniversalReceiverDelegateUP } from
    "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1UniversalReceiverDelegateUP/LSP1UniversalReceiverDelegateUP.sol";
import { UniversalFactoryDeployer } from "./DeployUniversalFactory.s.sol";

contract DeployProfileInfrastructure is UniversalFactoryDeployer {
    bytes32 public constant LSP23_FACTORY_SALT = keccak256("UG_LSP23_LINKED_CONTRACTS_FACTORY_V1");
    bytes32 public constant UP_POST_DEPLOYMENT_MODULE_SALT = keccak256("UG_UP_INIT_POST_DEPLOYMENT_MODULE_V1");
    bytes32 public constant UNIVERSAL_PROFILE_INIT_SALT = keccak256("UG_UNIVERSAL_PROFILE_INIT_V1");
    bytes32 public constant LSP6_KEY_MANAGER_INIT_SALT = keccak256("UG_LSP6_KEY_MANAGER_INIT_V1");
    bytes32 public constant LSP1_URD_UP_SALT = keccak256("UG_LSP1_URD_UP_V1");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        LSP16UniversalFactory universalFactory = LSP16UniversalFactory(deployUniversalFactory());

        address lsp23 = _deployContract(
            universalFactory,
            type(LSP23LinkedContractsFactory).creationCode,
            LSP23_FACTORY_SALT,
            "LSP23LinkedContractsFactory"
        );

        address postDeploymentModule = _deployContract(
            universalFactory,
            type(UniversalProfileInitPostDeploymentModule).creationCode,
            UP_POST_DEPLOYMENT_MODULE_SALT,
            "UniversalProfileInitPostDeploymentModule"
        );

        address universalProfileInit = _deployContract(
            universalFactory,
            type(UniversalProfileInit).creationCode,
            UNIVERSAL_PROFILE_INIT_SALT,
            "UniversalProfileInit"
        );

        address keyManagerInit = _deployContract(
            universalFactory,
            type(LSP6KeyManagerInit).creationCode,
            LSP6_KEY_MANAGER_INIT_SALT,
            "LSP6KeyManagerInit"
        );

        address urdUP = _deployContract(
            universalFactory,
            type(LSP1UniversalReceiverDelegateUP).creationCode,
            LSP1_URD_UP_SALT,
            "LSP1UniversalReceiverDelegateUP"
        );

        vm.stopBroadcast();

        console.log("\n=== Profile Infrastructure Deployment Summary ===");
        console.log("LSP16UniversalFactory:", address(universalFactory));
        console.log("LSP23LinkedContractsFactory:", lsp23);
        console.log("UniversalProfileInitPostDeploymentModule:", postDeploymentModule);
        console.log("UniversalProfileInit:", universalProfileInit);
        console.log("LSP6KeyManagerInit:", keyManagerInit);
        console.log("LSP1UniversalReceiverDelegateUP:", urdUP);
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

        address deployedAddress = factory.deployCreate2(creationCode, salt);
        console.log(contractName, "deployed at:", deployedAddress);

        require(deployedAddress == expectedAddress, "Address mismatch");
        return deployedAddress;
    }
}
