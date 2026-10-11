// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RealWorldAssetV2} from "../src/RealWorldAssetV2.sol";

contract DeployRealWorldAssetV2 is Script {

    bytes32 public constant ORG_SLUG_DATA_KEY = keccak256(bytes("org_slug"));
    bytes32 public constant PRODUCT_ID_DATA_KEY = keccak256(bytes("product_id"));

    uint256 internal constant _EIP170_LIMIT = 24_576;

    function run() external returns (address asset) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address owner_ = vm.envAddress("RWA_V2_OWNER");
        address assetRegistry_ = vm.envAddress("ASSET_REGISTRY");
        address serviceRegistry_ = vm.envAddress("SERVICE_REGISTRY");
        address verifier_ = vm.envAddress("RWA_VERIFIER");

        string memory name_ = vm.envString("RWA_V2_NAME");
        string memory symbol_ = vm.envString("RWA_V2_SYMBOL");
        string memory orgSlug = vm.envString("RWA_V2_ORG_SLUG");
        string memory productId = vm.envString("RWA_V2_PRODUCT_ID");

        bool shouldAutoLink_ = vm.envOr("RWA_V2_AUTOLINK", true);

        _requirePreconditions(owner_, assetRegistry_, serviceRegistry_, verifier_, name_, symbol_);

        bytes32[] memory initDataKeys = new bytes32[](2);
        bytes[] memory initDataValues = new bytes[](2);
        initDataKeys[0] = ORG_SLUG_DATA_KEY;
        initDataValues[0] = bytes(orgSlug);
        initDataKeys[1] = PRODUCT_ID_DATA_KEY;
        initDataValues[1] = bytes(productId);

        vm.startBroadcast(deployerKey);
        RealWorldAssetV2 rwa = new RealWorldAssetV2(
            name_,
            symbol_,
            owner_,
            serviceRegistry_,
            assetRegistry_,
            verifier_,
            shouldAutoLink_,
            initDataKeys,
            initDataValues
        );
        vm.stopBroadcast();

        asset = address(rwa);

        console.log("\n=== RealWorldAssetV2 Deployment Summary ===");
        console.log("RealWorldAssetV2:", asset);
        console.log("  owner (org UP):", owner_);
        console.log("  assetRegistry:", assetRegistry_);
        console.log("  serviceRegistry:", serviceRegistry_);
        console.log("  verifier:", verifier_);
        console.log("  shouldAutoLink:", shouldAutoLink_);
        console.log("  name / symbol:", name_, symbol_);
        console.log("  org_slug / product_id:", orgSlug, productId);
        console.log("  runtime bytecode (bytes):", asset.code.length);
        console.log("  EIP-170 limit:", _EIP170_LIMIT);

        _assertDeployment(rwa, owner_, assetRegistry_, serviceRegistry_, verifier_, orgSlug, productId);

        console.log("\nNEXT: register assets and batch Merkle roots against this collection");
        console.log("      through the owning Universal Profile's execute().");
    }

    function _requirePreconditions(
        address owner_,
        address assetRegistry_,
        address serviceRegistry_,
        address verifier_,
        string memory name_,
        string memory symbol_
    ) internal view {
        require(owner_ != address(0), "DeployRWAV2: RWA_V2_OWNER is the zero address");
        require(
            owner_.code.length > 0,
            "DeployRWAV2: RWA_V2_OWNER has no code. It must be the ORGANISATION'S UNIVERSAL PROFILE, not the deploying key -- registerAsset/setBatchMerkleRoot are called through that profile's execute()"
        );

        require(assetRegistry_.code.length > 0, "DeployRWAV2: ASSET_REGISTRY has no code on this chain");
        require(serviceRegistry_.code.length > 0, "DeployRWAV2: SERVICE_REGISTRY has no code on this chain");
        require(verifier_.code.length > 0, "DeployRWAV2: RWA_VERIFIER has no code on this chain");

        (bool ok, bytes memory ret) =
            assetRegistry_.staticcall(abi.encodeWithSignature("isRegisteredAsset(address)", address(0)));
        require(ok && ret.length == 32, "DeployRWAV2: ASSET_REGISTRY does not answer isRegisteredAsset(address) -- wrong contract at that address");

        (bool okv, bytes memory retv) = verifier_.staticcall(abi.encodeWithSignature("registry()"));
        require(okv && retv.length == 32, "DeployRWAV2: RWA_VERIFIER does not answer registry() -- wrong contract at that address");
        address verifierRegistry = abi.decode(retv, (address));
        require(
            verifierRegistry == assetRegistry_,
            "DeployRWAV2: RWA_VERIFIER.registry() != ASSET_REGISTRY. The verifier would police a registry this collection never writes to"
        );

        require(bytes(name_).length > 0, "DeployRWAV2: RWA_V2_NAME is empty");
        require(bytes(symbol_).length > 0, "DeployRWAV2: RWA_V2_SYMBOL is empty");
    }

    function _assertDeployment(
        RealWorldAssetV2 rwa,
        address owner_,
        address assetRegistry_,
        address serviceRegistry_,
        address verifier_,
        string memory orgSlug,
        string memory productId
    ) internal view {
        require(rwa.owner() == owner_, "DeployRWAV2: owner() mismatch");
        require(address(rwa.assetRegistry()) == assetRegistry_, "DeployRWAV2: assetRegistry() mismatch");
        require(address(rwa.serviceRegistry()) == serviceRegistry_, "DeployRWAV2: serviceRegistry() mismatch");
        require(rwa.verifier() == verifier_, "DeployRWAV2: verifier() mismatch");

        require(rwa.possessionNonce(bytes32(0)) == 0, "DeployRWAV2: possessionNonce(0) != 0");
        require(rwa.itemKeyOf(bytes32(0)) == address(0), "DeployRWAV2: itemKeyOf(0) != 0");

        require(
            keccak256(rwa.getData(ORG_SLUG_DATA_KEY)) == keccak256(bytes(orgSlug)),
            "DeployRWAV2: org_slug did not round-trip through ERC725Y"
        );
        require(
            keccak256(rwa.getData(PRODUCT_ID_DATA_KEY)) == keccak256(bytes(productId)),
            "DeployRWAV2: product_id did not round-trip through ERC725Y"
        );

        require(address(rwa).code.length <= _EIP170_LIMIT, "DeployRWAV2: over the EIP-170 limit");

        console.log("  possessionNonce(0x00..00): 0  <- V2 CONFIRMED (V1 reverts on this call)");
    }
}
