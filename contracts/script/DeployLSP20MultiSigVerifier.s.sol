// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LSP20MultiSigAssetVerifierV2.sol";
import "../src/AssetRegistryV2.sol";

contract DeployLSP20MultiSigVerifier is Script {
    function run() external returns (address) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address registryAddr = vm.envAddress("ASSET_REGISTRY");
        require(registryAddr != address(0), "ASSET_REGISTRY not set");

        vm.startBroadcast(deployerKey);
        LSP20MultiSigAssetVerifierV2 verifier =
            new LSP20MultiSigAssetVerifierV2(AssetRegistryV2(registryAddr), true);
        vm.stopBroadcast();

        console.log("Deployed LSP20MultiSigAssetVerifierV2:", address(verifier));
        return address(verifier);
    }
}
