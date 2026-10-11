// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {RealWorldAssetsV3} from "../src/RealWorldAssetsV3.sol";
import {RealWorldAssetsV3Factory} from "../src/RealWorldAssetsV3Factory.sol";

contract DeployRealWorldAssetsV3Factory is Script {

    uint256 internal constant _EIP170_LIMIT = 24_576;

    function run() external returns (address factoryAddress) {

        require(
            block.chainid != 42,
            "chain 42: use script/DeployPasskeyAndV3Stack.s.sol, which pre-flights nonces and skips deployed steps"
        );
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        RealWorldAssetsV3Factory factory = new RealWorldAssetsV3Factory();
        vm.stopBroadcast();

        factoryAddress = address(factory);

        uint256 size;
        assembly {
            size := extcodesize(factoryAddress)
        }

        console.log("RealWorldAssetsV3Factory deployed:", factoryAddress);
        console.log("  runtime bytecode size:", size, "/", _EIP170_LIMIT);

        require(size > 0, "deployment produced no code");
        require(size <= _EIP170_LIMIT, "runtime bytecode exceeds EIP-170");

        address ownerForRehearsal = vm.envOr("RWA_OWNER", address(0));
        if (ownerForRehearsal != address(0)) {
            bytes32 rehearsalSalt = keccak256(abi.encodePacked("rehearsal", block.timestamp));
            address predicted = factory.computeAddress(
                rehearsalSalt, "Rehearsal", "RWA", ownerForRehearsal
            );

            address created = factory.createRealWorldAssetsV3Deterministic(
                "Rehearsal", "RWA", ownerForRehearsal, rehearsalSalt
            );

            require(created == predicted, "computeAddress disagreed with the deploy");
            require(
                RealWorldAssetsV3(payable(created)).owner() == ownerForRehearsal,
                "owner() is not RWA_OWNER: the factory would produce unmintable collections"
            );

            require(
                factory.createRealWorldAssetsV3Deterministic(
                    "Rehearsal", "RWA", ownerForRehearsal, rehearsalSalt
                ) == created,
                "a second call did not return the same collection"
            );

            console.log("  rehearsal OK - predicted, deployed and owned as expected (not broadcast)");
        } else {
            console.log("  RWA_OWNER unset - skipped the deploy rehearsal");
        }
    }
}
