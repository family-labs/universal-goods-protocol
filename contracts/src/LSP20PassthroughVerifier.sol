// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";

/**
 * @title LSP20PassthroughVerifier
 * @notice A no-op verifier that always allows the call and requests no post-call verification.
 * @dev Useful for testing, default routing, or when off-chain consent is not required.
 */
contract LSP20PassthroughVerifier is ILSP20 {
    function lsp20VerifyCall(address, address, address, uint256, bytes memory)
        external
        pure
        override
        returns (bytes4)
    {
        // return first 3 bytes of lsp20VerifyCall selector + 0x00 (no post-call verification)
        return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
    }

    function lsp20VerifyCallResult(bytes32, bytes memory) external pure override returns (bytes4) {
        return ILSP20.lsp20VerifyCallResult.selector;
    }
}
