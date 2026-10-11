// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {P256FallbackVerifier} from "../src/P256FallbackVerifier.sol";

contract DeployP256FallbackVerifier is Script {
    function run() external returns (address verifier) {
        require(
            block.chainid != 42,
            "chain 42: use script/DeployPasskeyAndV3Stack.s.sol, which pre-flights nonces and skips deployed steps"
        );
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        verifier = address(new P256FallbackVerifier());
        vm.stopBroadcast();

        console.log("P256FallbackVerifier deployed at", verifier);
    }
}
