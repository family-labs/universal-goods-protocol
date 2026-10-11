// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {P256DeployGate} from "./lib/P256DeployGate.sol";

contract DeployWebAuthnController is P256DeployGate {
    function run() external returns (address controller, address fallbackVerifier) {
        fallbackVerifier = vm.envOr("P256_FALLBACK_VERIFIER", address(0));
        console.log("P256 fallback verifier:", fallbackVerifier);

        bool live = _requireLiveP256Path(fallbackVerifier);

        require(
            block.chainid != LUKSO_MAINNET_CHAIN_ID,
            "chain 42: use script/DeployPasskeyAndV3Stack.s.sol, which pre-flights nonces and skips deployed steps"
        );

        _startBroadcast();
        address implementation = address(new WebAuthnSignerProxy());
        _simulateTheLiveChainsPrecompile(live);
        controller = address(new WebAuthnController(IP256Verifier(fallbackVerifier), implementation));
        vm.stopBroadcast();

        console.log("WebAuthnController deployed at", controller);
        _requireControllerMatchesTheChain(controller, live);
    }

    function _startBroadcast() internal {
        if (vm.envExists("PRIVATE_KEY")) vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        else vm.startBroadcast();
    }
}
