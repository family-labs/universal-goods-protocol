// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { LSP16UniversalFactory } from "@lukso/lsp-smart-contracts/contracts/LSP16UniversalFactory/LSP16UniversalFactory.sol";
import { UniversalFactoryDeployer } from "./DeployUniversalFactory.s.sol";
import { ServiceProviderRegistry } from "../src/ServiceProviderRegistry.sol";
import { AssetRegistryV2 } from "../src/AssetRegistryV2.sol";
import { LSP20MultiSigAssetVerifierV2 } from "../src/LSP20MultiSigAssetVerifierV2.sol";
import { RealWorldAssetInit } from "../src/RealWorldAssetInit.sol";
import { RealWorldAssetV2Init } from "../src/RealWorldAssetV2Init.sol";
import { RealWorldAssetLSP16Factory } from "../src/RealWorldAssetLSP16Factory.sol";
import { RealWorldAssetsV3Factory } from "../src/RealWorldAssetsV3Factory.sol";

contract DeployAssetInfrastructure is UniversalFactoryDeployer {

    bytes32 public constant SERVICE_PROVIDER_REGISTRY_SALT = keccak256("UG_SERVICE_PROVIDER_REGISTRY_V1");
    bytes32 public constant ASSET_REGISTRY_SALT = keccak256("UG_ASSET_REGISTRY_V2_V1");
    bytes32 public constant LSP20_MSIG_VERIFIER_SALT = keccak256("UG_LSP20_MSIG_VERIFIER_V2_V2");
    bytes32 public constant RWA_IMPLEMENTATION_SALT = keccak256("UG_RWA_INIT_IMPLEMENTATION_V1");
    bytes32 public constant RWA_DEPLOYMENT_FACTORY_SALT = keccak256("UG_RWA_LSP16_FACTORY_V1");

    bytes32 public constant RWA_V2_IMPLEMENTATION_SALT = keccak256("UG_RWA_V2_INIT_IMPLEMENTATION_V1");
    bytes32 public constant RWA_V2_DEPLOYMENT_FACTORY_SALT = keccak256("UG_RWA_V2_LSP16_FACTORY_V1");

    bytes32 public constant RWA_V3_FACTORY_SALT = keccak256("UG_RWA_V3_FACTORY_V1");

    function run() external {

        require(
            block.chainid != 42,
            "chain 42: this script would deploy a second RealWorldAssetsV3Factory; use script/DeployPasskeyAndV3Stack.s.sol"
        );
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        LSP16UniversalFactory universalFactory = _getOrDeployUniversalFactory();

        address serviceProviderRegistryAddress = _deployContract(
            universalFactory,
            abi.encodePacked(type(ServiceProviderRegistry).creationCode, abi.encode(deployer)),
            SERVICE_PROVIDER_REGISTRY_SALT,
            "ServiceProviderRegistry"
        );

        address assetRegistryAddress = _deployContract(
            universalFactory,
            abi.encodePacked(type(AssetRegistryV2).creationCode, abi.encode(deployer)),
            ASSET_REGISTRY_SALT,
            "AssetRegistryV2"
        );

        address verifierAddress = _deployContract(
            universalFactory,
            abi.encodePacked(
                type(LSP20MultiSigAssetVerifierV2).creationCode,
                abi.encode(AssetRegistryV2(assetRegistryAddress), true)
            ),
            LSP20_MSIG_VERIFIER_SALT,
            "LSP20MultiSigAssetVerifierV2"
        );

        address rwaImplementationAddress = _deployContract(
            universalFactory,
            type(RealWorldAssetInit).creationCode,
            RWA_IMPLEMENTATION_SALT,
            "RealWorldAssetInit"
        );

        address rwaFactoryAddress = _deployContract(
            universalFactory,
            abi.encodePacked(
                type(RealWorldAssetLSP16Factory).creationCode,
                abi.encode(address(universalFactory), rwaImplementationAddress)
            ),
            RWA_DEPLOYMENT_FACTORY_SALT,
            "RealWorldAssetLSP16Factory"
        );

        address rwaV2ImplementationAddress = _deployContract(
            universalFactory,
            type(RealWorldAssetV2Init).creationCode,
            RWA_V2_IMPLEMENTATION_SALT,
            "RealWorldAssetV2Init"
        );

        address rwaV2FactoryAddress = _deployContract(
            universalFactory,
            abi.encodePacked(
                type(RealWorldAssetLSP16Factory).creationCode,
                abi.encode(address(universalFactory), rwaV2ImplementationAddress)
            ),
            RWA_V2_DEPLOYMENT_FACTORY_SALT,
            "RealWorldAssetLSP16Factory (V2)"
        );

        address rwaV3FactoryAddress = _deployContract(
            universalFactory,
            type(RealWorldAssetsV3Factory).creationCode,
            RWA_V3_FACTORY_SALT,
            "RealWorldAssetsV3Factory"
        );

        vm.stopBroadcast();

        console.log("\n=== Asset Infrastructure Deployment Summary ===");
        console.log("LSP16UniversalFactory:", address(universalFactory));
        console.log("ServiceProviderRegistry:", serviceProviderRegistryAddress);
        console.log("AssetRegistryV2:", assetRegistryAddress);
        console.log("LSP20MultiSigAssetVerifierV2:", verifierAddress);
        console.log("RealWorldAssetInit:", rwaImplementationAddress);
        console.log("RealWorldAssetLSP16Factory:", rwaFactoryAddress);
        console.log("RealWorldAssetV2Init:", rwaV2ImplementationAddress);
        console.log("RealWorldAssetLSP16Factory (V2):", rwaV2FactoryAddress);
        console.log("");
        console.log("RealWorldAssetsV3Factory:", rwaV3FactoryAddress);
        console.log("");
        console.log("=> record RealWorldAssetLSP16Factory (V2) as `rwaDeploymentFactoryV2`");
        console.log("   and RealWorldAssetsV3Factory as `realWorldAssetsV3Factory`");
        console.log("   in packages/network-config/src/contracts.ts for this chain.");
    }

    function _getOrDeployUniversalFactory() internal returns (LSP16UniversalFactory) {

        address expectedAddress = computeFactoryAddress();
        address factoryAddress = deployUniversalFactory();

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
