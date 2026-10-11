// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AssetRegistry.sol";

contract AssetRegistryTest is Test {
    AssetRegistry reg;
    address owner = address(0xABCD);
    address signer;
    address target = address(0x3333);
    address asset = address(0x4444);

    function setUp() public {
        vm.prank(owner);
        reg = new AssetRegistry(owner, true);
    }

    function testOwnerCanWhitelistAndRegisterWithSignature() public {

        uint256 pk = 0xBEEF;
        signer = vm.addr(pk);

        vm.prank(owner);
        reg.registerAsset(asset);
        vm.prank(owner);
        reg.whitelistSigner(asset, signer, true);
        assertTrue(reg.isSignerWhitelisted(asset, signer));

        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1000;

        bytes32 REGISTER_TYPEHASH =
            keccak256("Register(address target,address asset,uint256 nonce,uint256 deadline)");
        bytes32 DOMAIN_TYPEHASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 nameHash = keccak256(bytes("AssetRegistry"));
        bytes32 versionHash = keccak256(bytes("1"));

        bytes32 structHash =
            keccak256(abi.encode(REGISTER_TYPEHASH, target, asset, nonce, deadline));
        bytes32 domain = keccak256(
            abi.encode(DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(reg))
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(address(this));
        reg.registerWithSignature(target, asset, signer, nonce, deadline, sig);

        assertTrue(reg.isActive(asset, target));
        assertTrue(reg.signerLinkedAsset(signer) == asset);
        assertTrue(reg.usedNonce(signer, nonce));
    }
}
