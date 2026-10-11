// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";

/**
 * @title LSP20AuditOnlyVerifier
 * @notice Lightweight verifier used to emit audit events for pre- and post-call observations.
 * @dev Emits `AuditPre` before the call and requests a post-call hook so `AuditPost` can
 *      include the call result. No signature checks are performed here.
 */
contract LSP20AuditOnlyVerifier is ILSP20 {
    event AuditPre(address indexed target, address indexed caller, bytes4 selector, bytes data);
    event AuditPost(bytes32 indexed callHash, bytes result);

    function lsp20VerifyCall(
        address,
        address target,
        address caller,
        uint256,
        bytes memory callData
    ) external override returns (bytes4) {
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }
        emit AuditPre(target, caller, selector, callData);
        // request post-call so we can emit the result too
        return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x01)));
    }

    function lsp20VerifyCallResult(bytes32 callHash, bytes memory callResult)
        external
        override
        returns (bytes4)
    {
        emit AuditPost(callHash, callResult);
        return ILSP20.lsp20VerifyCallResult.selector;
    }
}
