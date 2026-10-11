// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";

contract SimpleProfile {
    // ERC725Y-like storage
    mapping(bytes32 => bytes) private _store;

    // LSP20 verifier
    address public verifier;

    event DataChanged(bytes32 indexed dataKey, bytes dataValue);

    constructor(address _verifier) {
        verifier = _verifier;
    }

    receive() external payable {}

    function setData(bytes32 dataKey, bytes memory dataValue) public {
        _store[dataKey] = dataValue;
        emit DataChanged(dataKey, dataValue);
    }

    function getData(bytes32 dataKey) public view returns (bytes memory) {
        return _store[dataKey];
    }

    // Verifies the call through LSP20, then executes the payload on self
    function executeWithVerification(bytes memory payload) public returns (bytes memory) {
        // Call verifier first
        bytes4 magic = ILSP20(verifier).lsp20VerifyCall(msg.sender, address(this), msg.sender, 0, payload);

        // Expected magic: first 3 bytes of selector + 0x00 (no post-verify)
        bytes4 expected = bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
        require(magic == expected, "Invalid magic value");

        // Execute the call on self
        (bool success, bytes memory result) = address(this).call(payload);
        require(success, "Execution failed");
        return result;
    }

    function transferValue(address payable to, uint256 amount) external {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Value transfer failed");
    }
}
