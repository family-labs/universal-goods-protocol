// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

/**
 * @title IP256Verifier
 * @notice The narrow interface `WebAuthnController` uses to reach a pure-Solidity P-256 verifier
 *         on chains that have no RIP-7212 precompile.
 * @dev This lives in its own file ON PURPOSE. Foundry compiles a file together with its imports,
 *      and `P256FallbackVerifier` is pinned to the legacy pipeline (see foundry.toml), so importing
 *      the interface from that file would drag every importer into the legacy pipeline too. An
 *      interface with no implementation and no imports is the seam that keeps the two build
 *      profiles apart.
 */
interface IP256Verifier {
    function verify(bytes32 messageHash, uint256 r, uint256 s, uint256 publicKeyX, uint256 publicKeyY)
        external
        view
        returns (bool);
}
