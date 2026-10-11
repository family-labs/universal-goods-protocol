// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {AssetRegistryV2} from "./AssetRegistryV2.sol";

/**
 * @title AssetRegistryFactory
 * @notice Factory contract for deploying AssetRegistry instances.
 */
/**
 * @title AssetRegistryFactory
 * @notice Factory contract for deploying `AssetRegistry` instances with sane defaults.
 */
contract AssetRegistryFactory {
    event AssetRegistryDeployed(address indexed registry, address indexed owner);

    function createAssetRegistry(address owner) external returns (address) {
        AssetRegistryV2 registry = new AssetRegistryV2(owner);
        emit AssetRegistryDeployed(address(registry), owner);
        return address(registry);
    }
}
