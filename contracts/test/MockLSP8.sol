// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import { LSP8IdentifiableDigitalAsset } from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import { _LSP4_TOKEN_TYPE_NFT } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import { _LSP8_TOKENID_FORMAT_HASH } from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

contract MockLSP8 is LSP8IdentifiableDigitalAsset {
    constructor(address owner) LSP8IdentifiableDigitalAsset("Mock", "MCK", owner, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_HASH) {}

    function mint(address to, bytes32 tokenId) public {
        _mint(to, tokenId, true, "");
    }
}
