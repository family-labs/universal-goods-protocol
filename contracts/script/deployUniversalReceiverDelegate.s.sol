// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import { LSP1UniversalReceiverDelegateUP } from "@lukso/lsp1delegate-contracts/contracts/LSP1UniversalReceiverDelegateUP.sol";

contract DeployLSP1UniversalReceiverDelegateUP is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        LSP1UniversalReceiverDelegateUP delegate = new LSP1UniversalReceiverDelegateUP();

        console.log("LSP1UniversalReceiverDelegateUP deployed at:", address(delegate));

        vm.stopBroadcast();
    }
}
