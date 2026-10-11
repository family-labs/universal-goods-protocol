// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {RealWorldAsset} from "./RealWorldAsset.sol";

/**
 * @title RealWorldAssetFactory
 * @notice Factory for deploying RealWorldAsset instances. It forwards constructor args as-is.
 */
contract RealWorldAssetFactory {
    event RealWorldAssetDeployed(address indexed rwa, address indexed owner);

    function createRealWorldAsset(
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink,
        bytes32[] memory initDataKeys,
        bytes[] memory initDataValues
    ) external returns (address) {
        RealWorldAsset rwa = new RealWorldAsset(
            name,
            symbol,
            owner,
            svcRegistry,
            assetRegistry,
            verifier,
            shouldAutoLink,
            initDataKeys,
            initDataValues
        );
        emit RealWorldAssetDeployed(address(rwa), owner);

        return address(rwa);
    }
}
