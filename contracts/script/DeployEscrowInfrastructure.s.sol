// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LSP16UniversalFactory} from "@lukso/lsp-smart-contracts/contracts/LSP16UniversalFactory/LSP16UniversalFactory.sol";
import {DeployUniversalFactory} from "./DeployUniversalFactory.s.sol";
import {MockStablecoin} from "../src/MockStablecoin.sol";
import {DataLinkedEscrow} from "../src/DataLinkedEscrow.sol";

contract DeployEscrowInfrastructure is Script {

    bytes32 public constant MOCK_STABLECOIN_SALT = keccak256("UG_MOCK_STABLECOIN_V1");
    bytes32 public constant DATA_LINKED_ESCROW_SALT = keccak256("UG_DATA_LINKED_ESCROW_V1");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        LSP16UniversalFactory universalFactory = _getOrDeployUniversalFactory();

        address stablecoinAddress = _deployContract(
            universalFactory,
            abi.encodePacked(type(MockStablecoin).creationCode, abi.encode(deployer)),
            MOCK_STABLECOIN_SALT,
            "MockStablecoin"
        );

        address escrowAddress = _deployContract(
            universalFactory,
            type(DataLinkedEscrow).creationCode,
            DATA_LINKED_ESCROW_SALT,
            "DataLinkedEscrow"
        );

        vm.stopBroadcast();

        console.log("\n=== Escrow Infrastructure Deployment Summary ===");
        console.log("LSP16UniversalFactory:", address(universalFactory));
        console.log("MockStablecoin:", stablecoinAddress);
        console.log("DataLinkedEscrow:", escrowAddress);
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
