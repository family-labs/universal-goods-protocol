// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP16UniversalFactory} from "@lukso/lsp16-contracts/contracts/LSP16UniversalFactory.sol";
import {RealWorldAssetInit} from "./RealWorldAssetInit.sol";

/**
 * @title RealWorldAssetLSP16Factory
 * @notice Deploy `RealWorldAsset` contracts deterministically through `LSP16UniversalFactory`.
 * @dev Uses LSP16 `deployCreate2` and `computeAddress` so deployment semantics are identical
 *      across chains where the same LSP16 factory address is used.
 */
contract RealWorldAssetLSP16Factory {
    LSP16UniversalFactory public immutable universalFactory;
    address public immutable implementation;

    event RealWorldAssetDeployedDeterministic(
        address indexed rwa, address indexed owner, bytes32 indexed salt
    );

    constructor(address universalFactory_, address implementation_) {
        require(universalFactory_ != address(0), "RWAFactory: zero universal factory");
        require(implementation_ != address(0), "RWAFactory: zero implementation");
        universalFactory = LSP16UniversalFactory(universalFactory_);
        implementation = implementation_;
    }

    /**
     * @notice Deploy a `RealWorldAsset` deterministically via LSP16 with the provided salt.
     */
    function createRealWorldAssetDeterministic(
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink,
        bytes32[] memory initDataKeys,
        bytes[] memory initDataValues,
        bytes32 salt
    ) external returns (address rwa) {
        bytes memory initializeCalldata = _getInitializeCalldata(
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

        rwa = universalFactory.deployERC1167ProxyAndInitialize(
            implementation,
            salt,
            initializeCalldata
        );
        require(rwa != address(0), "RWAFactory: deployment failed");

        emit RealWorldAssetDeployedDeterministic(rwa, owner, salt);
    }

    /// @notice Returns keccak256(initializationCalldata) for the provided init args.
    function getInitCodeHash(
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink,
        bytes32[] memory initDataKeys,
        bytes[] memory initDataValues
    ) public pure returns (bytes32) {
        bytes memory initializeCalldata = _getInitializeCalldata(
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
        return keccak256(initializeCalldata);
    }

    /// @notice Predict the proxy address that will be created via LSP16 for given init args.
    function computeAddress(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink,
        bytes32[] memory initDataKeys,
        bytes[] memory initDataValues
    ) public view returns (address) {
        bytes memory initializeCalldata = _getInitializeCalldata(
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

        return universalFactory.computeERC1167Address(implementation, salt, true, initializeCalldata);
    }

    function _getInitializeCalldata(
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink,
        bytes32[] memory initDataKeys,
        bytes[] memory initDataValues
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            RealWorldAssetInit.initialize.selector,
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
    }
}
