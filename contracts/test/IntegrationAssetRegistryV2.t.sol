// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";

contract IntegrationAssetRegistryV2Test is Test {
    AssetRegistryV2 public registry;
    RealWorldAsset public rwa;
    LSP20MultiSigAssetVerifierV2 public verifier;

    uint256 public pkA = 0xA11CE;
    uint256 public pkB = 0xB0B;

    address public signerA;
    address public signerB;

    address public deployer;

    bytes32 public constant ACTIVATE_TYPEHASH = keccak256(
        "Activate(address target,address asset,uint256 nonce,uint256 deadline,uint256 configVersion)"
    );
    bytes32 public constant OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        deployer = address(this);
        signerA = vm.addr(pkA);
        signerB = vm.addr(pkB);

        vm.deal(signerA, 1 ether);
        vm.deal(signerB, 1 ether);

        registry = new AssetRegistryV2(deployer);
        rwa = new RealWorldAsset(
            "RealWorldAsset",
            "RWA",
            deployer,
            address(0),
            address(registry),
            address(0),
            true,
            new bytes32[](0),
            new bytes[](0)
        );
        verifier = new LSP20MultiSigAssetVerifierV2(registry, true);

        vm.prank(deployer);
        rwa.updateVerifier(address(verifier));
    }

    function test_full_flow() public {

        vm.prank(deployer);
        registry.registerAsset(address(rwa));

        address[] memory signers = new address[](2);
        bool[] memory allowed = new bool[](2);

        signers[0] = signerA;
        signers[1] = signerB;

        allowed[0] = true;
        allowed[1] = true;

        vm.prank(deployer);
        registry.whitelistSigners(address(rwa), signers, allowed);

        vm.prank(deployer);
        registry.linkSigner(address(rwa), signerA);

        assertTrue(registry.isActive(address(rwa), address(rwa)));

        bytes32 tokenId = keccak256(abi.encodePacked("token-001"));
        bytes4 selector = bytes4(keccak256("mintWithRegistration(address,bytes32,bool,bytes)"));

        bytes32 dataHash = keccak256(abi.encodePacked(""));
        uint256 opDeadline = block.timestamp + 1 hours;
        bytes32 opStruct = keccak256(
            abi.encode(
                OPERATION_TYPEHASH,
                address(rwa),
                selector,
                signerB,
                signerB,
                address(rwa),
                tokenId,
                dataHash,
                uint256(0),
                uint256(0),
                opDeadline
            )
        );

        bytes32 nameHash = keccak256(bytes("LSP20MultiSigV2"));
        bytes32 verDomainTypeHash = keccak256(
            bytes(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            )
        );
        bytes32 verVersionHash = keccak256(bytes("1"));
        bytes32 verDomain = keccak256(
            abi.encode(verDomainTypeHash, nameHash, verVersionHash, block.chainid, address(rwa))
        );
        bytes32 opDigest = keccak256(abi.encodePacked("\x19\x01", verDomain, opStruct));

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(pkA, opDigest);
        bytes memory assetSig = abi.encodePacked(r2, s2, v2);
        bytes[] memory assetSigs = new bytes[](1);
        assetSigs[0] = assetSig;

        bytes memory sigEnvelope =
            abi.encode(uint256(0), opDeadline, address(rwa), assetSigs, bytes(""));
        bytes memory dataWithSig = abi.encode(bytes(""), sigEnvelope);

        bytes4 mintSelector = bytes4(keccak256("mintWithRegistration(address,bytes32,bool,bytes)"));
        bytes memory mintCalldata =
            abi.encodeWithSelector(mintSelector, signerB, tokenId, true, address(rwa), dataWithSig);

        bool isActive = registry.isActive(address(rwa), address(rwa));
        assertTrue(isActive, "registry active expected");
        bool isSignerLinked = registry.isSignerForAsset(address(rwa), signerA);
        assertTrue(isSignerLinked, "signerA should be linked for asset");

        bytes32 rpart;
        bytes32 spart;
        uint8 vpart;
        assembly {
            rpart := mload(add(assetSig, 0x20))
            spart := mload(add(assetSig, 0x40))
            vpart := byte(0, mload(add(assetSig, 0x60)))
        }
        address recovered = ecrecover(opDigest, vpart, rpart, spart);
        assertEq(recovered, signerA, "recovered signer mismatch");

        emit log_bytes(abi.encodePacked(selector));
        emit log_uint(mintCalldata.length);

        vm.prank(signerB);
        rwa.mintWithRegistration(signerB, tokenId, true, dataWithSig);

        address owner = rwa.tokenOwnerOf(tokenId);
        assertEq(owner, signerB);

        (address boundAsset, bytes32 boundToken) = registry.getSignerBinding(signerB);
        assertEq(boundAsset, address(rwa));
        assertEq(boundToken, tokenId);
    }
}
