// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {DemoLSP8Token} from "../src/DemoLSP8Token.sol";
import {LSP20Router} from "../src/LSP20Router.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";
import {LSP20StrictPolicyVerifier} from "../src/LSP20StrictPolicyVerifier.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";

contract Phase5_StrictTest is Test {
    DemoLSP8Token token;
    LSP20Router router;
    LSP20PassthroughVerifier pass;
    LSP20StrictPolicyVerifier strictV;
    AssetRegistry registry;

    uint256 platformKey = 0xA11A;
    address platform;
    uint256 userKey = 0xB22B;
    address user;
    uint256 assetKey = 0xC33C;
    address asset;

    function setUp() public {
        platform = vm.addr(platformKey);
        user = vm.addr(userKey);
        asset = vm.addr(assetKey);

        router = new LSP20Router(address(this));
        pass = new LSP20PassthroughVerifier();
        registry = new AssetRegistry(address(this), true);
        strictV = new LSP20StrictPolicyVerifier(registry, platform, false);

        token = new DemoLSP8Token("Demo", "DL8", address(this), address(router));
        router.setDefaultVerifier(address(token), address(pass));

        router.setVerifierForSelector(
            address(token), token.mintWithVerification.selector, address(strictV)
        );

        registry.setAssetStatus(address(token), asset, true);
    }

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 domainTypehash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 nameHash = keccak256(bytes("LSP20Strict"));
        bytes32 versionHash = keccak256(bytes("1"));
        return keccak256(
            abi.encode(domainTypehash, nameHash, versionHash, block.chainid, address(token))
        );
    }

    function _signMint(
        address to,
        bytes32 tokenId,
        bytes memory data,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    )
        internal
        view
        returns (bytes memory assetSig, bytes memory userSig, bytes memory platformSig)
    {
        bytes32 ds = _domainSeparator();
        bytes32 opTypehash = keccak256(
            "Operation(address target,bytes4 selector,address to,address assetAddr,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                opTypehash,
                address(token),
                token.mintWithVerification.selector,
                to,
                asset,
                tokenId,
                keccak256(data),
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", ds, structHash));
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(assetKey, digest);
            assetSig = abi.encodePacked(r, s, v);
        }
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);
            userSig = abi.encodePacked(r, s, v);
        }
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(platformKey, digest);
            platformSig = abi.encodePacked(r, s, v);
        }
    }

    function testMintRequiresPlatformAssetUser() public {
        bytes32 tokenId = keccak256("s1");
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;
        (bytes memory assetSig, bytes memory userSig, bytes memory platformSig) =
            _signMint(user, tokenId, "", 0, nonce, deadline);

        bytes memory badPlatformSig = platformSig;
        badPlatformSig[0] = bytes1(uint8(badPlatformSig[0]) ^ 0x01);
        vm.expectRevert(LSP20StrictPolicyVerifier.STR_BadPlatformSig.selector);
        token.mintWithVerification(
            user,
            tokenId,
            true,
            abi.encode("", abi.encode(nonce, deadline, asset, assetSig, userSig, badPlatformSig))
        );

        (assetSig, userSig, platformSig) = _signMint(user, tokenId, "", 0, nonce + 1, deadline);
        token.mintWithVerification(
            user,
            tokenId,
            true,
            abi.encode("", abi.encode(nonce + 1, deadline, asset, assetSig, userSig, platformSig))
        );
        assertEq(token.tokenOwnerOf(tokenId), user);
    }

    function testAssetUniquenessPerTarget() public {
        bytes32 tokenId1 = keccak256("u1");
        bytes32 tokenId2 = keccak256("u2");
        uint256 deadline = block.timestamp + 1 hours;

        (bytes memory assetSig1, bytes memory userSig1, bytes memory platformSig1) =
            _signMint(user, tokenId1, "", 0, 10, deadline);
        token.mintWithVerification(
            user,
            tokenId1,
            true,
            abi.encode("", abi.encode(10, deadline, asset, assetSig1, userSig1, platformSig1))
        );

        (bytes memory assetSig2, bytes memory userSig2, bytes memory platformSig2) =
            _signMint(user, tokenId2, "", 0, 11, deadline);
        vm.expectRevert(LSP20StrictPolicyVerifier.STR_AssetAlreadyUsed.selector);
        token.mintWithVerification(
            user,
            tokenId2,
            true,
            abi.encode("", abi.encode(11, deadline, asset, assetSig2, userSig2, platformSig2))
        );
    }

    function testMintFailsWhenAssetRevoked() public {
        bytes32 tokenId = keccak256("s2");
        uint256 nonce = 5;
        uint256 deadline = block.timestamp + 1 hours;
        (bytes memory assetSig, bytes memory userSig, bytes memory platformSig) =
            _signMint(user, tokenId, "", 0, nonce, deadline);

        registry.setAssetStatus(address(token), asset, false);
        vm.expectRevert(LSP20StrictPolicyVerifier.STR_AssetRevoked.selector);
        token.mintWithVerification(
            user,
            tokenId,
            true,
            abi.encode("", abi.encode(nonce, deadline, asset, assetSig, userSig, platformSig))
        );
    }
}
