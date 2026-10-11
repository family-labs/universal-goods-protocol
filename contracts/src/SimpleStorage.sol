// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SimpleStorage
/// @notice Minimal contract to store and retrieve a string value by a bytes32 key
contract SimpleStorage {
    mapping(bytes32 => string) private store;

    /// @notice Set the value for a given key
    /// @param key The key to set
    /// @param value The string value to store
    function set(bytes32 key, string calldata value) external {
        store[key] = value;
    }

    /// @notice Get the value for a given key
    /// @param key The key to query
    /// @return The stored string value (empty if not set)
    function get(bytes32 key) external view returns (string memory) {
        return store[key];
    }
}
