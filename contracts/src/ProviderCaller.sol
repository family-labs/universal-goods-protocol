// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

contract ProviderCaller {
    /// @notice Calls recordServiceEvent on the target RWA contract on behalf of this contract
    function callRecord(address rwa, bytes32 tokenId, bytes calldata dataWithSig) external {
        (bool ok, bytes memory ret) = rwa.call(
            abi.encodeWithSignature("recordServiceEvent(bytes32,bytes)", tokenId, dataWithSig)
        );
        require(ok, string(ret));
    }
}
