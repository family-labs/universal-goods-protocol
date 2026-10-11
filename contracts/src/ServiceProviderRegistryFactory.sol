// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ServiceProviderRegistry} from "./ServiceProviderRegistry.sol";

/**
 * @title ServiceProviderRegistryFactory
 * @notice Minimal factory for deploying ServiceProviderRegistry instances.
 */
/**
 * @title ServiceProviderRegistryFactory
 * @notice Factory for deploying `ServiceProviderRegistry` instances.
 */
contract ServiceProviderRegistryFactory {
    event ServiceProviderRegistryDeployed(address indexed registry, address indexed owner);

    function createServiceProviderRegistry(address owner) external returns (address) {
        ServiceProviderRegistry registry = new ServiceProviderRegistry(owner);
        emit ServiceProviderRegistryDeployed(address(registry), owner);
        return address(registry);
    }
}
