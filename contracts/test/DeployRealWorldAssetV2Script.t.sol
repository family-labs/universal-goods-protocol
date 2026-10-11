// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployRealWorldAssetV2} from "../script/DeployRealWorldAssetV2.s.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {RealWorldAssetV2} from "../src/RealWorldAssetV2.sol";
import {RWAPossessionGate} from "../src/RWAPossessionGate.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";

contract DeployRealWorldAssetV2ScriptTest is Test {
    AssetRegistryV2 internal registry;
    ServiceProviderRegistry internal serviceReg;
    LSP20MultiSigAssetVerifierV2 internal verifier;
    DeployRealWorldAssetV2 internal script;

    OrgProfileStub internal orgUP;

    RealWorldAssetV2 internal rwa;

    uint256 internal constant PK_ITEM_A = 0xA11CE;
    address internal itemKeyA;
    bytes32 internal tokenIdA = keccak256("item-A");

    address internal buyer = address(0x600D);

    string internal constant ORG_SLUG = "acme-batteries";
    string internal constant PRODUCT_ID = "6b1f0f9e-0000-4000-8000-000000000001";

    bytes32 internal constant POSSESSION_TYPEHASH = keccak256(
        "Possession(address asset,bytes32 tokenId,address from,address to,uint256 nonce,uint256 deadline)"
    );
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant MSIG_OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    event PossessionProofAccepted(
        bytes32 indexed tokenId, address indexed itemKey, address indexed to, uint256 nonce
    );

    function setUp() public {
        itemKeyA = vm.addr(PK_ITEM_A);

        registry = new AssetRegistryV2(address(this));
        serviceReg = new ServiceProviderRegistry(address(this));
        verifier = new LSP20MultiSigAssetVerifierV2(registry, true);

        orgUP = new OrgProfileStub();

        script = new DeployRealWorldAssetV2();

        vm.setEnv("PRIVATE_KEY", "1");
        vm.setEnv("RWA_V2_OWNER", vm.toString(address(orgUP)));
        vm.setEnv("ASSET_REGISTRY", vm.toString(address(registry)));
        vm.setEnv("SERVICE_REGISTRY", vm.toString(address(serviceReg)));
        vm.setEnv("RWA_VERIFIER", vm.toString(address(verifier)));
        vm.setEnv("RWA_V2_NAME", "Acme Battery Passport");
        vm.setEnv("RWA_V2_SYMBOL", "ACMEBAT");
        vm.setEnv("RWA_V2_ORG_SLUG", ORG_SLUG);
        vm.setEnv("RWA_V2_PRODUCT_ID", PRODUCT_ID);
    }

    function _runScript() internal returns (RealWorldAssetV2) {
        return RealWorldAssetV2(payable(script.run()));
    }

    function test_script_deploys_a_collection_wired_exactly_as_production_expects() public {
        RealWorldAssetV2 a = _runScript();

        assertEq(a.owner(), address(orgUP), "owner must be the org UP, not the deployer");
        assertEq(address(a.assetRegistry()), address(registry), "assetRegistry");
        assertEq(address(a.serviceRegistry()), address(serviceReg), "serviceRegistry");
        assertEq(a.verifier(), address(verifier), "verifier");

        assertEq(a.possessionNonce(bytes32(0)), 0, "possessionNonce must answer 0");

        assertEq(string(a.getData(script.ORG_SLUG_DATA_KEY())), ORG_SLUG, "org_slug");
        assertEq(string(a.getData(script.PRODUCT_ID_DATA_KEY())), PRODUCT_ID, "product_id");
    }

    function test_a_V1_collection_does_NOT_answer_possessionNonce() public {
        RealWorldAsset v1 = new RealWorldAsset(
            "V1", "V1", address(orgUP), address(serviceReg), address(registry),
            address(verifier), true, new bytes32[](0), new bytes[](0)
        );
        (bool ok,) = address(v1).staticcall(
            abi.encodeWithSignature("possessionNonce(bytes32)", bytes32(0))
        );
        assertFalse(ok, "V1 must NOT answer possessionNonce -- the detector depends on it");
    }

    function test_rehearsal_register_whitelist_mint_initiate_accept() public {
        rwa = _runScript();

        orgUP.exec(
            address(registry), abi.encodeCall(AssetRegistryV2.registerAsset, (address(rwa)))
        );
        assertTrue(registry.isRegisteredAsset(address(rwa)), "asset must be registered");

        address[] memory signers = new address[](1);
        bool[] memory allowed = new bool[](1);
        signers[0] = itemKeyA;
        allowed[0] = true;
        orgUP.exec(
            address(registry),
            abi.encodeCall(AssetRegistryV2.whitelistSigners, (address(rwa), signers, allowed))
        );
        assertTrue(registry.isSignerForAsset(address(rwa), itemKeyA), "item key whitelisted");

        uint256 deadline = block.timestamp + 1 hours;
        _mintWithItemKey(tokenIdA, itemKeyA, PK_ITEM_A, address(orgUP), deadline);

        assertEq(rwa.tokenOwnerOf(tokenIdA), address(orgUP), "minted to the maker profile");
        assertEq(rwa.itemKeyOf(tokenIdA), itemKeyA, "the item key is snapshotted at mint");
        assertEq(rwa.possessionNonce(tokenIdA), 0, "a fresh token starts at nonce 0");

        orgUP.exec(
            address(rwa),
            abi.encodeCall(
                RealWorldAsset.initiateTokenOwnershipTransfer,
                (tokenIdA, buyer, abi.encode(bytes(""), bytes("")))
            )
        );
        assertEq(rwa.pendingTokenOwner(tokenIdA), buyer, "buyer is pending");

        bytes memory proof =
            _signPossession(PK_ITEM_A, tokenIdA, address(orgUP), buyer, 0, deadline);

        vm.expectEmit(true, true, true, true, address(rwa));
        emit PossessionProofAccepted(tokenIdA, itemKeyA, buyer, 0);

        vm.prank(buyer);
        rwa.acceptTokenOwnership(
            tokenIdA, true, abi.encode(abi.encode(deadline, proof, bytes("")), bytes(""))
        );

        assertEq(rwa.tokenOwnerOf(tokenIdA), buyer, "the token moved");
        assertEq(rwa.possessionNonce(tokenIdA), 1, "the possession nonce burned");
    }

    function test_control_the_same_accept_WITHOUT_a_proof_does_not_move_the_token() public {
        rwa = _runScript();
        orgUP.exec(
            address(registry), abi.encodeCall(AssetRegistryV2.registerAsset, (address(rwa)))
        );
        address[] memory signers = new address[](1);
        bool[] memory allowed = new bool[](1);
        signers[0] = itemKeyA;
        allowed[0] = true;
        orgUP.exec(
            address(registry),
            abi.encodeCall(AssetRegistryV2.whitelistSigners, (address(rwa), signers, allowed))
        );
        uint256 deadline = block.timestamp + 1 hours;
        _mintWithItemKey(tokenIdA, itemKeyA, PK_ITEM_A, address(orgUP), deadline);
        orgUP.exec(
            address(rwa),
            abi.encodeCall(
                RealWorldAsset.initiateTokenOwnershipTransfer,
                (tokenIdA, buyer, abi.encode(bytes(""), bytes("")))
            )
        );

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_MissingPossessionProof.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, abi.encode(bytes(""), bytes("")));

        assertEq(rwa.tokenOwnerOf(tokenIdA), address(orgUP), "the token must NOT have moved");
        assertEq(rwa.possessionNonce(tokenIdA), 0, "and the nonce must be unspent");
    }

    function _mintWithItemKey(
        bytes32 tokenId,
        address itemKey,
        uint256 itemPk,
        address to,
        uint256 deadline
    ) internal {
        bytes memory opData = abi.encode(itemKey, bytes(""));
        uint256 nonce = uint256(tokenId);

        bytes32 opHash = keccak256(
            abi.encode(
                MSIG_OPERATION_TYPEHASH,
                address(rwa),
                RWAPossessionGate.mintWithItemKey.selector,
                to,
                to,
                address(rwa),
                tokenId,
                keccak256(opData),
                uint256(0),
                nonce,
                deadline
            )
        );
        bytes32 domain = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("LSP20MultiSigV2")),
                keccak256(bytes("1")),
                block.chainid,
                address(rwa)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(itemPk, keccak256(abi.encodePacked("\x19\x01", domain, opHash)));

        bytes[] memory assetSigs = new bytes[](1);
        assetSigs[0] = abi.encodePacked(r, s, v);

        bytes memory envelope =
            abi.encode(nonce, deadline, address(rwa), assetSigs, bytes(""));

        orgUP.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey,
                (to, tokenId, true, abi.encode(opData, envelope))
            )
        );
    }

    function _signPossession(
        uint256 pk,
        bytes32 tokenId,
        address from,
        address to,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(POSSESSION_TYPEHASH, address(rwa), tokenId, from, to, nonce, deadline)
        );
        bytes32 domain = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("UniversalGoodsRWAv2")),
                keccak256(bytes("1")),
                block.chainid,
                address(rwa)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pk, keccak256(abi.encodePacked("\x19\x01", domain, structHash)));
        return abi.encodePacked(r, s, v);
    }
}

contract OrgProfileStub {
    function exec(address target, bytes memory data) external returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }
}
