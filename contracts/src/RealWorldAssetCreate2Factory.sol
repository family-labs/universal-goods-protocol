// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {RealWorldAsset} from "./RealWorldAsset.sol";

/**
 * @title RealWorldAssetCreate2Factory
 * @notice Deploy `RealWorldAsset` contracts deterministically using CREATE2.
 *         Provides helper functions to compute init code hash and predicted address.
 */
contract RealWorldAssetCreate2Factory {
    event RealWorldAssetDeployedDeterministic(
        address indexed rwa, address indexed owner, bytes32 indexed salt
    );

    /**
     * @notice Deploy a `RealWorldAsset` using CREATE2 with the provided salt.
     * @dev The deployed address is keccak256(0xff, address(this), salt, keccak256(init_code))[12:]
     */
    function createRealWorldAssetDeterministic(
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink,
        bytes32 salt
    ) external returns (address rwa) {
        bytes memory bytecode = abi.encodePacked(
            type(RealWorldAsset).creationCode,
            abi.encode(
                name,
                symbol,
                owner,
                svcRegistry,
                assetRegistry,
                verifier,
                shouldAutoLink,
                new bytes32[](0),
                new bytes[](0)
            )
        );

        assembly {
            rwa := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        require(rwa != address(0), "Create2: deployment failed");

        emit RealWorldAssetDeployedDeterministic(rwa, owner, salt);
    }

    /// @notice Returns keccak256(init_code) for the provided constructor args
    function getInitCodeHash(
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink
    ) public pure returns (bytes32) {
        bytes memory bytecode = abi.encodePacked(
            type(RealWorldAsset).creationCode,
            abi.encode(
                name,
                symbol,
                owner,
                svcRegistry,
                assetRegistry,
                verifier,
                shouldAutoLink,
                new bytes32[](0),
                new bytes[](0)
            )
        );
        return keccak256(bytecode);
    }

    /// @notice Predict the address that will be created by this factory for given salt and
    /// constructor args
    function computeAddress(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address owner,
        address svcRegistry,
        address assetRegistry,
        address verifier,
        bool shouldAutoLink
    ) public view returns (address) {
        bytes32 initCodeHash = getInitCodeHash(
            name,
            symbol,
            owner,
            svcRegistry,
            assetRegistry,
            verifier,
            shouldAutoLink
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash));
        return address(uint160(uint256(hash)));
    }
}
