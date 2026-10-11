// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

interface ILSP20Verifier {
    /// @notice Verifies that `signature` was produced by the required signer for `hash`
    /// @param hash The 32-byte message hash that was signed (pre-hashed according to the client)
    /// @param signature The 65-byte ECDSA signature (r||s||v)
    /// @return valid true if signature recovered to the configured signer
    function verify(bytes32 hash, bytes memory signature) external view returns (bool valid);

    /// @notice Returns the configured required signer address
    function requiredSigner() external view returns (address);
}
