// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {RealWorldAssetsV3} from "../src/RealWorldAssetsV3.sol";
import {RealWorldAssetsV3Factory} from "../src/RealWorldAssetsV3Factory.sol";
import {MockOrgProfile} from "./RealWorldAssetsV3OwnerGate.t.sol";

contract RealWorldAssetsV3FactoryTest is Test {
    RealWorldAssetsV3Factory internal factory;
    MockOrgProfile internal orgProfile;
    MockOrgProfile internal otherProfile;

    address internal deployer = address(0xDEbA5E7);
    address internal stranger = address(0xBAD);

    string internal constant NAME = "Universal Goods Passport";
    string internal constant SYMBOL = "RWA";
    bytes32 internal constant SALT = keccak256("product-42");

    bytes32 internal constant LSP4_TOKEN_TYPE_KEY =
        0xe0261fa95db2eb3b5439bd033cda66d56b96f92f243a8228fd87550ed7bdfdb3;

    event RealWorldAssetsV3Deployed(
        address indexed collection, address indexed owner, bytes32 indexed salt
    );
    event RealWorldAssetsV3AlreadyDeployed(
        address indexed collection, address indexed owner, bytes32 indexed salt
    );

    function setUp() public {
        factory = new RealWorldAssetsV3Factory();
        orgProfile = new MockOrgProfile();
        otherProfile = new MockOrgProfile();
    }

    function _deploy(address owner_) internal returns (address) {
        vm.prank(deployer);
        return factory.createRealWorldAssetsV3Deterministic(NAME, SYMBOL, owner_, SALT);
    }

    function test_TheOwnerIsTheOrgProfile_NotTheCaller_NotTheFactory() public {
        address collection = _deploy(address(orgProfile));
        address owner_ = RealWorldAssetsV3(payable(collection)).owner();

        assertEq(owner_, address(orgProfile), "owner must be the org profile passed in");

        assertTrue(owner_ != deployer, "the caller who paid must NOT be the owner");
        assertTrue(owner_ != address(factory), "the factory must NOT be the owner");
    }

    function test_TheDeployedCollectionMintsForItsOwner() public {
        address collection = _deploy(address(orgProfile));
        bytes32 tokenId = keccak256("https://ugpdpp.org/01/07090055120115/21/000001");

        orgProfile.execute(
            collection,
            abi.encodeWithSelector(
                RealWorldAssetsV3.mint.selector, address(orgProfile), tokenId, false, bytes("")
            )
        );

        assertEq(RealWorldAssetsV3(payable(collection)).tokenOwnerOf(tokenId), address(orgProfile));
    }

    function test_TheDeployerCannotMintFromWhatTheyDeployed() public {
        address collection = _deploy(address(orgProfile));

        vm.prank(deployer);
        vm.expectRevert();
        RealWorldAssetsV3(payable(collection)).mint(deployer, keccak256("STOLEN"), true, "");
    }

    function test_AStrangerCannotMintFromIt() public {
        address collection = _deploy(address(orgProfile));

        vm.prank(stranger);
        vm.expectRevert();
        RealWorldAssetsV3(payable(collection)).mint(stranger, keccak256("STOLEN"), true, "");
    }

    function test_ItsTokenTypeIsCollection_WhichIsWhatTheDetectorProbesFor() public {
        address collection = _deploy(address(orgProfile));
        bytes memory raw = RealWorldAssetsV3(payable(collection)).getData(LSP4_TOKEN_TYPE_KEY);

        assertEq(raw.length, 32, "LSP4 stores abi.encode(uint256), so exactly 32 bytes");
        assertEq(abi.decode(raw, (uint256)), 2, "token type must be COLLECTION (2), not NFT (1)");
    }

    function test_TheSelectorsTypeScriptEncodesAreTheOnesThisContractAnswers() public pure {
        assertEq(
            RealWorldAssetsV3Factory.createRealWorldAssetsV3Deterministic.selector,
            bytes4(0xf735e6f0),
            "off-chain deploy clients encode this signature - update both or neither"
        );
        assertEq(
            RealWorldAssetsV3Factory.computeAddress.selector,
            bytes4(0xc5ff1d47),
            "off-chain deploy clients read the predicted address with this signature"
        );
    }

    function test_ComputeAddressPredictsTheDeployBeforeItHappens() public {
        address predicted = factory.computeAddress(SALT, NAME, SYMBOL, address(orgProfile));
        assertEq(predicted.code.length, 0, "nothing there yet");

        address actual = _deploy(address(orgProfile));
        assertEq(actual, predicted, "a client saved this address before the deploy landed");
    }

    function test_IsDeployedFlipsFalseToTrue() public {
        assertFalse(factory.isDeployed(SALT, NAME, SYMBOL, address(orgProfile)));
        _deploy(address(orgProfile));
        assertTrue(factory.isDeployed(SALT, NAME, SYMBOL, address(orgProfile)));
    }

    function test_ADifferentOwnerIsADifferentAddress() public view {
        assertTrue(
            factory.computeAddress(SALT, NAME, SYMBOL, address(orgProfile))
                != factory.computeAddress(SALT, NAME, SYMBOL, address(otherProfile))
        );
    }

    function test_ADifferentNameOrSymbolIsADifferentAddress() public view {
        address base = factory.computeAddress(SALT, NAME, SYMBOL, address(orgProfile));
        assertTrue(base != factory.computeAddress(SALT, "Other", SYMBOL, address(orgProfile)));
        assertTrue(base != factory.computeAddress(SALT, NAME, "OTH", address(orgProfile)));
    }

    function test_ADifferentSaltIsADifferentAddress() public view {
        assertTrue(
            factory.computeAddress(SALT, NAME, SYMBOL, address(orgProfile))
                != factory.computeAddress(keccak256("product-43"), NAME, SYMBOL, address(orgProfile))
        );
    }

    function testFuzz_ComputeAddressAlwaysMatchesTheDeploy(bytes32 salt, address owner_) public {
        vm.assume(owner_ != address(0));
        address predicted = factory.computeAddress(salt, NAME, SYMBOL, owner_);

        vm.prank(deployer);
        address actual = factory.createRealWorldAssetsV3Deterministic(NAME, SYMBOL, owner_, salt);

        assertEq(actual, predicted);
        assertEq(RealWorldAssetsV3(payable(actual)).owner(), owner_);
    }

    function test_DeployingTwiceReturnsTheSameCollectionAndDoesNotRevert() public {
        address first = _deploy(address(orgProfile));
        address second = _deploy(address(orgProfile));
        assertEq(second, first);
    }

    function test_TheSecondCallSaysAlreadyDeployed_SoLogsDoNotClaimAPhantomDeploy() public {
        address predicted = factory.computeAddress(SALT, NAME, SYMBOL, address(orgProfile));

        vm.expectEmit(true, true, true, true, address(factory));
        emit RealWorldAssetsV3Deployed(predicted, address(orgProfile), SALT);
        _deploy(address(orgProfile));

        vm.expectEmit(true, true, true, true, address(factory));
        emit RealWorldAssetsV3AlreadyDeployed(predicted, address(orgProfile), SALT);
        _deploy(address(orgProfile));
    }

    function test_AFrontRunnerCanOnlyDeployOurCollectionForUs() public {
        address predicted = factory.computeAddress(SALT, NAME, SYMBOL, address(orgProfile));

        vm.prank(stranger);
        address theirs =
            factory.createRealWorldAssetsV3Deterministic(NAME, SYMBOL, address(orgProfile), SALT);

        assertEq(theirs, predicted);

        assertEq(RealWorldAssetsV3(payable(theirs)).owner(), address(orgProfile));

        assertEq(_deploy(address(orgProfile)), predicted);
    }

    function test_RefusesTheZeroOwner() public {
        vm.prank(deployer);
        vm.expectRevert(RealWorldAssetsV3Factory.V3Factory_ZeroOwner.selector);
        factory.createRealWorldAssetsV3Deterministic(NAME, SYMBOL, address(0), SALT);
    }

    function test_RefusesAnEmptyName() public {
        vm.prank(deployer);
        vm.expectRevert(RealWorldAssetsV3Factory.V3Factory_EmptyName.selector);
        factory.createRealWorldAssetsV3Deterministic("", SYMBOL, address(orgProfile), SALT);
    }

    function test_RefusesAnEmptySymbol() public {
        vm.prank(deployer);
        vm.expectRevert(RealWorldAssetsV3Factory.V3Factory_EmptySymbol.selector);
        factory.createRealWorldAssetsV3Deterministic(NAME, "", address(orgProfile), SALT);
    }

    function test_TheFactoryHoldsNoAuthorityOverWhatItDeploys() public {
        address collection = _deploy(address(orgProfile));

        vm.prank(address(factory));
        vm.expectRevert();
        RealWorldAssetsV3(payable(collection)).mint(address(factory), keccak256("X"), true, "");
    }
}
