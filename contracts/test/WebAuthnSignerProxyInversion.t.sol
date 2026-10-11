// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";

contract PermissionedKeyManagerMock {
    address public immutable account;
    mapping(address => bool) public permitted;

    address public lastCaller;
    bytes public lastPayload;
    uint256 public executions;

    error NoPermissionsSet(address caller);

    constructor(address account_) {
        account = account_;
    }

    function grant(address controller) external {
        permitted[controller] = true;
    }

    function execute(bytes calldata payload) external payable returns (bytes memory) {
        if (!permitted[msg.sender]) revert NoPermissionsSet(msg.sender);
        lastCaller = msg.sender;
        lastPayload = payload;
        executions += 1;
        return "";
    }
}

contract ProfileMock {
    address public owner;

    function setOwner(address owner_) external {
        owner = owner_;
    }
}

contract WebAuthnSignerProxyInversionTest is Test {
    WebAuthnController internal controller;
    address internal implementation;

    ProfileMock internal profile;
    PermissionedKeyManagerMock internal keyManager;

    ProfileMock internal otherProfile;
    PermissionedKeyManagerMock internal otherKeyManager;

    bytes32 internal credentialId;
    bytes32 internal secondCredentialId;

    uint256 internal constant CUSTOMER_KEY = 1;
    uint256 internal constant PUB_X =
        0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 internal constant PUB_Y =
        0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    function setUp() public {
        implementation = address(new WebAuthnSignerProxy());
        controller = new WebAuthnController(IP256Verifier(address(0)), implementation);

        profile = new ProfileMock();
        keyManager = new PermissionedKeyManagerMock(address(profile));
        profile.setOwner(address(keyManager));

        otherProfile = new ProfileMock();
        otherKeyManager = new PermissionedKeyManagerMock(address(otherProfile));
        otherProfile.setOwner(address(otherKeyManager));

        credentialId = keccak256("passkey-one");
        secondCredentialId = keccak256("passkey-two");

        _bootstrap(address(profile), credentialId);
        _bootstrap(address(otherProfile), secondCredentialId);
    }

    function testTheKeyManagerSeesTheProxyAsTheCaller() public {
        address proxy = controller.deploySignerProxy(address(profile), credentialId);
        keyManager.grant(proxy);

        _execute(proxy, address(profile), credentialId, 0, address(0xBEEF), 1 ether, hex"1234");

        assertEq(keyManager.executions(), 1, "the payload must have reached the Key Manager");
        assertEq(keyManager.lastCaller(), proxy, "the LSP6 permission subject must be the proxy");
        assertTrue(
            keyManager.lastCaller() != address(controller),
            "the shared controller must NOT be the subject: that is the defect being removed"
        );
    }

    function testGrantingTheControllerAloneAuthorisesNothing() public {
        address proxy = controller.deploySignerProxy(address(profile), credentialId);
        keyManager.grant(address(controller));

        WebAuthn.Assertion memory assertion =
            _assertionFor(address(profile), credentialId, 0, 0, address(0xBEEF), 1 ether, hex"1234");

        vm.expectRevert(
            abi.encodeWithSelector(
                PermissionedKeyManagerMock.NoPermissionsSet.selector, proxy
            )
        );
        WebAuthnSignerProxy(payable(proxy)).executeUP(0, address(0xBEEF), 1 ether, hex"1234", assertion);

        assertEq(keyManager.executions(), 0, "no execution may have occurred");
    }

    function testAProxyCannotActForAnotherProfilesCredential() public {
        address proxy = controller.deploySignerProxy(address(profile), credentialId);
        address otherProxy =
            controller.deploySignerProxy(address(otherProfile), secondCredentialId);

        keyManager.grant(proxy);
        otherKeyManager.grant(otherProxy);

        otherKeyManager.grant(proxy);

        WebAuthn.Assertion memory assertion = _assertionFor(
            address(otherProfile), secondCredentialId, 0, 0, address(0xBEEF), 1 ether, hex"1234"
        );

        vm.prank(proxy);
        vm.expectRevert(WebAuthnController.NotThisCredentialsSignerProxy.selector);
        controller.authoriseExecUP(
            address(otherProfile), secondCredentialId, 0, address(0xBEEF), 1 ether, hex"1234", assertion
        );

        assertEq(otherKeyManager.executions(), 0, "the victim profile must show no execution");
        assertEq(
            controller.credentialNonces(address(otherProfile), secondCredentialId),
            0,
            "the victim credential's nonce must not have moved"
        );
    }

    function testAnArbitraryCallerCannotBurnACredentialsNonce() public {
        controller.deploySignerProxy(address(profile), credentialId);
        WebAuthn.Assertion memory assertion =
            _assertionFor(address(profile), credentialId, 0, 0, address(0xBEEF), 1 ether, hex"1234");

        vm.prank(address(0xDEAD));
        vm.expectRevert(WebAuthnController.NotThisCredentialsSignerProxy.selector);
        controller.authoriseExecUP(
            address(profile), credentialId, 0, address(0xBEEF), 1 ether, hex"1234", assertion
        );

        assertEq(
            controller.credentialNonces(address(profile), credentialId), 0, "nonce must not move"
        );
    }

    function testTheProxyCanActRepeatedlyAsTheNonceAdvances() public {
        address proxy = controller.deploySignerProxy(address(profile), credentialId);
        keyManager.grant(proxy);

        for (uint256 i = 0; i < 3; i++) {
            _execute(proxy, address(profile), credentialId, i, address(0xBEEF), i, hex"aa");
        }

        assertEq(keyManager.executions(), 3, "all three operations must have executed");
        assertEq(
            controller.credentialNonces(address(profile), credentialId), 3, "nonce must be 3"
        );
    }

    function testPermissionsCanBeGrantedToAnAddressThatHasNoCodeYet() public {
        address predicted = controller.signerProxyFor(address(profile), credentialId);

        assertEq(predicted.code.length, 0, "precondition: nothing deployed yet");
        assertFalse(
            controller.isSignerProxyDeployed(address(profile), credentialId),
            "isSignerProxyDeployed must report the truth BEFORE deployment"
        );

        keyManager.grant(predicted);
        assertTrue(keyManager.permitted(predicted), "the grant succeeds and looks correct");

        assertEq(keyManager.executions(), 0, "no execution is possible against an empty address");

        address proxy = controller.deploySignerProxy(address(profile), credentialId);
        assertEq(proxy, predicted, "deployment must land exactly at the predicted address");
        assertTrue(
            controller.isSignerProxyDeployed(address(profile), credentialId),
            "isSignerProxyDeployed must flip once code exists"
        );

        _execute(proxy, address(profile), credentialId, 0, address(0xBEEF), 1, hex"bb");
        assertEq(keyManager.executions(), 1, "the same grant now works");
    }

    function testDeploymentIsIdempotent() public {
        address first = controller.deploySignerProxy(address(profile), credentialId);
        address second = controller.deploySignerProxy(address(profile), credentialId);
        assertEq(first, second, "a second deployment must return the same address, not revert");
    }

    function testTheAddressCannotBeOccupiedByDifferentCode() public {
        address predicted = controller.signerProxyFor(address(profile), credentialId);

        vm.prank(address(0xA77ACC));
        address deployed = controller.deploySignerProxy(address(profile), credentialId);
        assertEq(deployed, predicted, "an attacker-initiated deployment lands at the same address");

        WebAuthnSignerProxy proxy = WebAuthnSignerProxy(payable(deployed));
        assertEq(address(proxy.controller()), address(controller), "controller is not a free choice");
        assertEq(proxy.profile(), address(profile), "profile is fixed by the salt");
        assertEq(proxy.credentialId(), credentialId, "credentialId is fixed by the salt");

        vm.prank(address(0xA77ACC));
        vm.expectRevert(WebAuthnSignerProxy.AlreadyInitialized.selector);
        proxy.initialize(address(0xBAD), address(otherProfile), secondCredentialId);
    }

    function testADifferentImplementationDerivesADifferentAddress() public {
        WebAuthnController other = new WebAuthnController(
            IP256Verifier(address(0)), address(new WebAuthnSignerProxy())
        );
        assertTrue(
            other.signerProxyFor(address(profile), credentialId)
                != controller.signerProxyFor(address(profile), credentialId),
            "the proxy address must depend on the implementation"
        );
    }

    function testTheAddressDependsOnBothProfileAndCredential() public view {
        address base = controller.signerProxyFor(address(profile), credentialId);
        assertTrue(
            controller.signerProxyFor(address(otherProfile), credentialId) != base,
            "changing the profile must move the address"
        );
        assertTrue(
            controller.signerProxyFor(address(profile), secondCredentialId) != base,
            "changing the credential must move the address"
        );
    }

    function testMeasureProxyDeploymentGas() public {
        uint256 before = gasleft();
        controller.deploySignerProxy(address(profile), credentialId);
        uint256 used = before - gasleft();
        emit log_named_uint("gas: deploySignerProxy (clone + initialize)", used);

        uint256 before2 = gasleft();
        controller.signerProxyFor(address(profile), credentialId);
        uint256 used2 = before2 - gasleft();
        emit log_named_uint("gas: signerProxyFor (view)", used2);
    }

    function _bootstrap(address profile_, bytes32 credId) internal {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                address(controller),
                profile_,
                credId,
                PUB_X,
                PUB_Y,
                uint256(0)
            )
        );

        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(digest, CUSTOMER_KEY);
        vm.prank(profile_);
        controller.registerCredential(profile_, credId, PUB_X, PUB_Y, assertion);
    }

    function _assertionFor(
        address profile_,
        bytes32 credId,
        uint256 nonce,
        uint256 operationType,
        address target,
        uint256 value,
        bytes memory data
    ) internal view returns (WebAuthn.Assertion memory) {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"),
                block.chainid,
                address(controller),
                profile_,
                credId,
                nonce,
                operationType,
                target,
                value,
                keccak256(data)
            )
        );
        return WebAuthnFixture.make(digest, CUSTOMER_KEY);
    }

    function _execute(
        address proxy,
        address profile_,
        bytes32 credId,
        uint256 nonce,
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        WebAuthn.Assertion memory assertion =
            _assertionFor(profile_, credId, nonce, 0, target, value, data);
        WebAuthnSignerProxy(payable(proxy)).executeUP(0, target, value, data, assertion);
    }
}
