// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP7DigitalAsset} from
    "@lukso/lsp7-contracts/contracts/LSP7DigitalAsset.sol";
import {_LSP4_TOKEN_TYPE_TOKEN} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

/// @title MockStablecoin
/// @notice LSP7 fungible token with public mint for demo/testing purposes.
contract MockStablecoin is LSP7DigitalAsset {
    constructor(address owner_)
        LSP7DigitalAsset("Mock USDC", "mUSDC", owner_, _LSP4_TOKEN_TYPE_TOKEN, false)
    {}

    /// @notice Mint tokens to any address (demo only — no access control).
    function mint(address to, uint256 amount) external {
        _mint(to, amount, true, "");
    }
}
