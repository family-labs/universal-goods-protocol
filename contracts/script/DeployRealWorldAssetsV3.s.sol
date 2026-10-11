// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {RealWorldAssetsV3, requireRwaSymbol} from "../src/RealWorldAssetsV3.sol";

contract DeployRealWorldAssetsV3 is Script {

    uint256 internal constant _EIP170_LIMIT = 24_576;

    function run() external returns (address asset) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address owner_ = vm.envAddress("RWA_OWNER");
        string memory name_ = vm.envString("RWA_NAME");
        string memory symbol_ = vm.envString("RWA_SYMBOL");

        require(owner_ != address(0), "RWA_OWNER must not be the zero address");
        require(bytes(name_).length > 0, "RWA_NAME must not be empty");
        require(bytes(symbol_).length > 0, "RWA_SYMBOL must not be empty");

        requireRwaSymbol(symbol_);

        vm.startBroadcast(deployerKey);
        RealWorldAssetsV3 collection = new RealWorldAssetsV3(name_, symbol_, owner_);
        vm.stopBroadcast();

        asset = address(collection);

        uint256 size;
        assembly {
            size := extcodesize(asset)
        }

        console.log("RealWorldAssetsV3 deployed:", asset);
        console.log("  owner (org Universal Profile):", owner_);
        console.log("  runtime bytecode size:", size, "/", _EIP170_LIMIT);

        require(collection.owner() == owner_, "owner() does not match RWA_OWNER after deploy");

        require(size > 0, "deployment produced no code");
        require(size <= _EIP170_LIMIT, "runtime bytecode exceeds EIP-170");
    }
}
