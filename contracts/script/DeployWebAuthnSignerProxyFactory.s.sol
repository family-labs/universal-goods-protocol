// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {WebAuthnSignerProxyFactory} from "../src/WebAuthnSignerProxyFactory.sol";

contract DeployWebAuthnSignerProxyFactory is Script {
    function run() external returns (address implementation, address factory) {
        require(
            block.chainid != 42,
            "chain 42: use script/DeployPasskeyAndV3Stack.s.sol, which pre-flights nonces and skips deployed steps"
        );
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        WebAuthnSignerProxy impl = new WebAuthnSignerProxy();
        WebAuthnSignerProxyFactory proxyFactory = new WebAuthnSignerProxyFactory(address(impl));
        vm.stopBroadcast();

        implementation = address(impl);
        factory = address(proxyFactory);

        console.log("WebAuthnSignerProxy implementation:", implementation);
        console.log("WebAuthnSignerProxyFactory:", factory);
    }
}
