// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {DemoLSP8Token} from "../src/DemoLSP8Token.sol";
import {LSP20Router} from "../src/LSP20Router.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";
import {LSP20ServiceProviderVerifier} from "../src/LSP20ServiceProviderVerifier.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";

contract Phase6_ServiceProviderTest is Test {
    DemoLSP8Token token;
    LSP20Router router;
    LSP20PassthroughVerifier pass;
    LSP20ServiceProviderVerifier spv;
    ServiceProviderRegistry registry;

    uint256 providerKey = 0xD44D;
    address provider;

    function setUp() public {
        provider = vm.addr(providerKey);
        router = new LSP20Router(address(this));
        pass = new LSP20PassthroughVerifier();
        registry = new ServiceProviderRegistry(address(this));
        spv = new LSP20ServiceProviderVerifier(registry);
        token = new DemoLSP8Token("Demo", "DL8", address(this), address(router));
        router.setDefaultVerifier(address(token), address(pass));
        router.setVerifierForSelectors(address(token), _selectors(), address(spv));
        registry.setProviderStatus(address(token), provider, true);
    }

    function _selectors() internal pure returns (bytes4[] memory sels) {
        sels = new bytes4[](2);
        sels[0] = DemoLSP8Token.setData.selector;
        sels[1] = DemoLSP8Token.setDataForTokenId.selector;
    }

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 domainTypehash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 nameHash = keccak256(bytes("LSP20ServiceProvider"));
        bytes32 versionHash = keccak256(bytes("1"));
        return keccak256(
            abi.encode(domainTypehash, nameHash, versionHash, block.chainid, address(token))
        );
    }

    function _signSetData(
        bytes32 dataKey,
        bytes memory dataValue,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory sig) {
        bytes32 ds = _domainSeparator();
        bytes32 opTypehash = keccak256(
            "Operation(address target,bytes4 selector,bytes32 dataKey,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                opTypehash,
                address(token),
                token.setData.selector,
                dataKey,
                keccak256(dataValue),
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", ds, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(providerKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _signSetDataForToken(
        bytes32 tokenId,
        bytes32 dataKey,
        bytes memory dataValue,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory sig) {
        bytes32 ds = _domainSeparator();
        bytes32 opTypehash = keccak256(
            "Operation(address target,bytes4 selector,bytes32 tokenId,bytes32 dataKey,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                opTypehash,
                address(token),
                token.setDataForTokenId.selector,
                tokenId,
                dataKey,
                keccak256(dataValue),
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", ds, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(providerKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function testSetDataRequiresActiveProviderAndSig() public {
        bytes32 k = keccak256("k6");
        bytes memory v = hex"aabb";
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signSetData(k, v, 0, nonce, deadline);

        bytes memory badSig = sig;
        badSig[0] = bytes1(uint8(badSig[0]) ^ 0x01);
        vm.expectRevert(LSP20ServiceProviderVerifier.SP_BadProviderSig.selector);
        token.setData(k, abi.encode(v, abi.encode(nonce, deadline, provider, badSig)));

        token.setData(
            k,
            abi.encode(
                v,
                abi.encode(
                    nonce + 1, deadline, provider, _signSetData(k, v, 0, nonce + 1, deadline)
                )
            )
        );
    }

    function testSetDataFailsWhenProviderRevoked() public {
        bytes32 k = keccak256("k7");
        bytes memory v = hex"ccdd";
        uint256 nonce = 10;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signSetData(k, v, 0, nonce, deadline);
        registry.setProviderStatus(address(token), provider, false);
        vm.expectRevert(LSP20ServiceProviderVerifier.SP_NotActive.selector);
        token.setData(k, abi.encode(v, abi.encode(nonce, deadline, provider, sig)));
    }

    function testSetDataForTokenIdRequiresSig() public {
        bytes32 tokenId = keccak256("t6");

        token.mintWithVerification(address(this), tokenId, true, abi.encode("", ""));

        bytes32 k = keccak256("k8");
        bytes memory v = hex"eeff";
        uint256 nonce = 21;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signSetDataForToken(tokenId, k, v, 0, nonce, deadline);

        token.setDataForTokenId(
            tokenId, k, abi.encode(v, abi.encode(nonce, deadline, provider, sig))
        );
    }
}
