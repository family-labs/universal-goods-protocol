// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS,
    _PERMISSION_CHANGEOWNER,
    _PERMISSION_DELEGATECALL,
    _PERMISSION_SUPER_DELEGATECALL,
    _PERMISSION_REENTRANCY,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised, NoPermissionsSet} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {LSP11SocialRecovery} from "@lukso/lsp11-contracts/contracts/LSP11SocialRecovery.sol";
import {LSP11_VERSION, _INTERFACEID_LSP11} from "@lukso/lsp11-contracts/contracts/LSP11Constants.sol";
import {
    CallerVotesHaveNotReachedThreshold,
    CannotRecoverBeforeDelay,
    CallerIsNotTheAccount,
    CallerIsNotGuardian,
    NotAGuardianOfTheAccount,
    CallerIsNotVotedAddress,
    AccountNotSetupYet,
    CannotVoteToAddressTwice,
    GuardianNumberCannotGoBelowThreshold
} from "@lukso/lsp11-contracts/contracts/LSP11Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";

interface IKM {
    function execute(bytes calldata payload) external payable returns (bytes memory);
}

interface IUP {
    function execute(uint256 operationType, address target, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory);
    function setData(bytes32 key, bytes calldata value) external payable;
    function setDataBatch(bytes32[] calldata keys, bytes[] calldata values) external payable;
}

contract LSP11ColleagueRecoveryTest is Test {
    LSP11SocialRecovery internal lsp11;
    WebAuthnController internal webauthn;

    LSP0ERC725Account internal owner;
    LSP6KeyManager internal ownerKM;
    uint256 internal constant LOST_BROWSER_PK = 0xB10B;
    address internal lostBrowserKey;
    bytes32 internal constant OWNER_CRED = keccak256("owner-passkey");
    uint256 internal constant OWNER_PASSKEY = 0x0111;
    address internal ownerProxy;
    uint256 internal ownerProxyNonce;
    address internal platformDelegate = makeAddr("platform-delegate");

    uint256 internal constant N_GUARDIANS = 3;
    LSP0ERC725Account[3] internal guardianUP;
    LSP6KeyManager[3] internal guardianKM;
    address[3] internal guardianProxy;
    uint256[3] internal guardianPasskey;
    uint256[3] internal guardianNonce;

    function _guardianCred(uint256 i) internal pure returns (bytes32) {
        return keccak256(abi.encode("guardian-passkey", i));
    }

    uint256 internal constant NEW_BROWSER_PK = 0xA11CE;
    address internal newBrowserKey;
    address internal relayer = makeAddr("relayer");
    uint256 internal constant THRESHOLD = 2;
    uint256 internal constant DELAY = 24 hours;

    bytes10 internal constant PERMISSIONS_PREFIX = 0x4b80742de2bf82acb363;
    bytes32 internal constant PASSPORT_KEY = keccak256("UG_VerifiableData_product_demo");

    bytes32 internal constant OWNER_KEY_PERMISSIONS = bytes32(
        type(uint256).max
            & ~uint256(_PERMISSION_CHANGEOWNER)
            & ~uint256(_PERMISSION_REENTRANCY)
            & ~uint256(_PERMISSION_DELEGATECALL)
            & ~uint256(_PERMISSION_SUPER_DELEGATECALL)
    );

    function setUp() public {
        vm.warp(1_790_000_000);
        lostBrowserKey = vm.addr(LOST_BROWSER_PK);
        newBrowserKey = vm.addr(NEW_BROWSER_PK);

        lsp11 = new LSP11SocialRecovery();
        webauthn = new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()));

        owner = new LSP0ERC725Account(address(this));
        ownerKM = new LSP6KeyManager(address(owner));
        ownerProxy = _enrolPasskey(address(owner), OWNER_CRED, OWNER_PASSKEY);
        _grant(owner, lostBrowserKey, OWNER_KEY_PERMISSIONS, 0);
        _grant(owner, ownerProxy, OWNER_KEY_PERMISSIONS, 1);
        _grant(owner, platformDelegate, _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA, 2);
        owner.setData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, abi.encodePacked(uint128(3)));
        _handOver(owner, ownerKM);

        for (uint256 i; i < N_GUARDIANS; i++) {
            guardianPasskey[i] = 0x6000 + i;
            guardianUP[i] = new LSP0ERC725Account(address(this));
            guardianKM[i] = new LSP6KeyManager(address(guardianUP[i]));
            guardianProxy[i] = _enrolPasskey(address(guardianUP[i]), _guardianCred(i), guardianPasskey[i]);
            _grant(guardianUP[i], guardianProxy[i], OWNER_KEY_PERMISSIONS, 0);
            guardianUP[i].setData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, abi.encodePacked(uint128(1)));
            _handOver(guardianUP[i], guardianKM[i]);
        }
    }

    function test_twoOfThreeGuardiansRecoverTheAccount() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);

        _guardianVotes(0, newBrowserKey);
        _guardianVotes(1, newBrowserKey);
        assertEq(lsp11.getVotesOfGuardianVotedAddress(address(owner), 0, newBrowserKey), 2);

        vm.warp(block.timestamp + DELAY);
        _recoverViaRelay(newBrowserKey, NEW_BROWSER_PK, _enrolmentPayload(newBrowserKey));

        assertEq(owner.getData(_permissionsKey(newBrowserKey)), abi.encodePacked(OWNER_KEY_PERMISSIONS));
        assertEq(owner.getData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY), abi.encodePacked(uint128(5)));
        assertEq(owner.getData(_arrayIndexKey(4)), abi.encodePacked(newBrowserKey));
        assertEq(lsp11.getRecoveryCounterOf(address(owner)), 1, "a new round starts");

        vm.prank(newBrowserKey);
        ownerKM.execute(abi.encodeCall(IUP.setData, (PASSPORT_KEY, hex"c0ffee")));
        assertEq(owner.getData(PASSPORT_KEY), hex"c0ffee", "the recovered key must be usable");

        vm.prank(newBrowserKey);
        ownerKM.execute(abi.encodeCall(IUP.setData, (_permissionsKey(lostBrowserKey), "")));
        assertEq(owner.getData(_permissionsKey(lostBrowserKey)).length, 0, "the lost key is revoked");
    }

    function test_newKeyCanRecoverDirectly() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _guardianVotes(0, newBrowserKey);
        _guardianVotes(2, newBrowserKey);
        vm.warp(block.timestamp + DELAY);

        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);
        assertEq(owner.getData(_permissionsKey(newBrowserKey)), abi.encodePacked(OWNER_KEY_PERMISSIONS));
    }

    function test_oneApprovalIsNotEnough() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _guardianVotes(0, newBrowserKey);
        vm.warp(block.timestamp + DELAY * 30);

        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(CallerVotesHaveNotReachedThreshold.selector, address(owner), newBrowserKey));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);
        assertEq(owner.getData(_permissionsKey(newBrowserKey)).length, 0);
    }

    function test_splitVotesDoNotAddUp() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        address otherKey = makeAddr("other-key");
        _guardianVotes(0, newBrowserKey);
        _guardianVotes(1, otherKey);
        vm.warp(block.timestamp + DELAY);

        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(CallerVotesHaveNotReachedThreshold.selector, address(owner), newBrowserKey));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);
    }

    function test_guardianCanWithdrawItsApproval() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _guardianVotes(0, newBrowserKey);
        _guardianVotes(1, newBrowserKey);
        _guardianVotes(1, address(0));
        assertEq(lsp11.getVotesOfGuardianVotedAddress(address(owner), 0, newBrowserKey), 1);

        vm.warp(block.timestamp + DELAY);
        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(CallerVotesHaveNotReachedThreshold.selector, address(owner), newBrowserKey));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);
    }

    function test_thresholdMetButDelayNotPassed() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _guardianVotes(0, newBrowserKey);
        _guardianVotes(1, newBrowserKey);
        vm.warp(block.timestamp + DELAY - 1);

        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(CannotRecoverBeforeDelay.selector, address(owner), DELAY));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);
    }

    function test_survivingPasskeyCancelsDuringTheDelay() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        uint256 attackerPk = 0xBAD;
        address attackerKey = vm.addr(attackerPk);
        _guardianVotes(0, attackerKey);
        _guardianVotes(1, attackerKey);

        vm.warp(block.timestamp + DELAY / 2);
        _ownerPasskeyCalls(address(lsp11), abi.encodeCall(LSP11SocialRecovery.cancelRecoveryProcess, (address(owner))));
        assertEq(lsp11.getRecoveryCounterOf(address(owner)), 1, "the round is cancelled");

        vm.warp(block.timestamp + DELAY);
        bytes memory payload = _enrolmentPayload(attackerKey);
        vm.prank(attackerKey);
        vm.expectRevert(abi.encodeWithSelector(CallerVotesHaveNotReachedThreshold.selector, address(owner), attackerKey));
        lsp11.recoverAccess(address(owner), attackerKey, bytes32(0), bytes32(0), payload);
        assertEq(owner.getData(_permissionsKey(attackerKey)).length, 0, "the attacker's key is never added");
    }

    function test_survivingBrowserKeyCancels() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _guardianVotes(0, newBrowserKey);
        vm.prank(lostBrowserKey);
        ownerKM.execute(
            abi.encodeCall(
                IUP.execute,
                (0, address(lsp11), 0, abi.encodeCall(LSP11SocialRecovery.cancelRecoveryProcess, (address(owner))))
            )
        );
        assertEq(lsp11.getRecoveryCounterOf(address(owner)), 1);
        assertEq(lsp11.getVotesOfGuardianVotedAddress(address(owner), 1, newBrowserKey), 0);
    }

    function test_onlyTheAccountCanCancel() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        vm.prank(address(guardianUP[0]));
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotTheAccount.selector, address(owner), address(guardianUP[0])));
        lsp11.cancelRecoveryProcess(address(owner));

        vm.prank(platformDelegate);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotTheAccount.selector, address(owner), platformDelegate));
        lsp11.cancelRecoveryProcess(address(owner));
    }

    function test_delayRunsFromTheFirstVoteOfTheRound() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _guardianVotes(0, newBrowserKey);
        uint256 firstVote = block.timestamp;
        assertEq(lsp11.getFirstRecoveryTimestampOf(address(owner), 0), firstVote);

        vm.warp(firstVote + 30 days);
        _guardianVotes(1, newBrowserKey);

        _recoverViaRelay(newBrowserKey, NEW_BROWSER_PK, _enrolmentPayload(newBrowserKey));
        assertEq(owner.getData(_permissionsKey(newBrowserKey)), abi.encodePacked(OWNER_KEY_PERMISSIONS));
    }

    function test_defaultDelayIsFortyMinutes() public view {
        assertEq(lsp11.getRecoveryDelayOf(address(owner)), 40 minutes);
        assertEq(lsp11.DEFAULT_RECOVERY_DELAY(), 40 minutes);
    }

    function test_aGuardianCannotRecoverToItselfAlone() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        uint256 rogueKeyPk = 0xD00D;
        address rogueKey = vm.addr(rogueKeyPk);
        _guardianVotes(0, rogueKey);
        vm.warp(block.timestamp + DELAY);

        bytes memory payload = _enrolmentPayload(rogueKey);
        vm.prank(rogueKey);
        vm.expectRevert(abi.encodeWithSelector(CallerVotesHaveNotReachedThreshold.selector, address(owner), rogueKey));
        lsp11.recoverAccess(address(owner), rogueKey, bytes32(0), bytes32(0), payload);

        _guardianVotes(0, address(guardianUP[0]));
        vm.prank(address(guardianUP[0]));
        vm.expectRevert(
            abi.encodeWithSelector(CallerVotesHaveNotReachedThreshold.selector, address(owner), address(guardianUP[0]))
        );
        lsp11.recoverAccess(address(owner), address(guardianUP[0]), bytes32(0), bytes32(0), payload);

        assertEq(owner.getData(_permissionsKey(rogueKey)).length, 0);
        assertEq(owner.getData(_permissionsKey(address(guardianUP[0]))).length, 0);
    }

    function test_aGuardianHasNoOtherRoute() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        address g0 = address(guardianUP[0]);

        _guardianVotes(0, newBrowserKey);
        vm.prank(g0);
        vm.expectRevert(abi.encodeWithSelector(CannotVoteToAddressTwice.selector, address(owner), g0, newBrowserKey));
        lsp11.voteForRecovery(address(owner), g0, newBrowserKey);

        vm.prank(g0);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotGuardian.selector, address(guardianUP[1]), g0));
        lsp11.voteForRecovery(address(owner), address(guardianUP[1]), newBrowserKey);

        vm.prank(g0);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotTheAccount.selector, address(owner), g0));
        lsp11.addGuardian(address(owner), makeAddr("sock-puppet"));

        vm.prank(g0);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotTheAccount.selector, address(owner), g0));
        lsp11.setGuardiansThreshold(address(owner), 1);

        bytes memory selfEnrol = _enrolmentPayload(g0);
        vm.prank(g0);
        vm.expectRevert(abi.encodeWithSelector(NoPermissionsSet.selector, g0));
        ownerKM.execute(selfEnrol);
        assertEq(owner.getData(_permissionsKey(g0)).length, 0);
    }

    function test_platformDelegateCannotTriggerRecovery() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        address platformKey = makeAddr("platform-key");

        bytes memory addKey = _enrolmentPayload(platformKey);
        vm.prank(platformDelegate);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, platformDelegate, "ADDCONTROLLER"));
        ownerKM.execute(addKey);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(LSP11SocialRecovery.addGuardian, (address(owner), platformDelegate));
        calls[1] = abi.encodeCall(LSP11SocialRecovery.setGuardiansThreshold, (address(owner), 1));
        vm.prank(platformDelegate);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, platformDelegate, "CALL"));
        ownerKM.execute(
            abi.encodeCall(IUP.execute, (0, address(lsp11), 0, abi.encodeCall(LSP11SocialRecovery.batchCalls, (calls))))
        );

        vm.prank(platformDelegate);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotTheAccount.selector, address(owner), platformDelegate));
        lsp11.addGuardian(address(owner), platformDelegate);
        vm.prank(platformDelegate);
        vm.expectRevert(abi.encodeWithSelector(NotAGuardianOfTheAccount.selector, address(owner), platformDelegate));
        lsp11.voteForRecovery(address(owner), platformDelegate, platformKey);

        vm.prank(platformDelegate);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, platformDelegate, "EDITPERMISSIONS"));
        ownerKM.execute(
            abi.encodeCall(
                IUP.setData, (_permissionsKey(address(lsp11)), abi.encodePacked(bytes32(type(uint256).max)))
            )
        );
        vm.prank(platformDelegate);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, platformDelegate, "EDITPERMISSIONS"));
        ownerKM.execute(
            abi.encodeCall(
                IUP.setData, (_permissionsKey(platformDelegate), abi.encodePacked(_PERMISSION_ADDCONTROLLER))
            )
        );

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(CallerIsNotVotedAddress.selector, platformKey, relayer));
        lsp11.recoverAccess(address(owner), platformKey, bytes32(0), bytes32(0), "");

        assertEq(lsp11.getGuardiansOf(address(owner)).length, 3);
        assertEq(lsp11.getGuardiansThresholdOf(address(owner)), THRESHOLD);
        assertEq(owner.getData(_permissionsKey(platformKey)).length, 0);
        assertEq(owner.getData(_permissionsKey(address(lsp11))), abi.encodePacked(_PERMISSION_ADDCONTROLLER));
    }

    function test_recoveryCanOnlyAddAKey() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _guardianVotes(0, newBrowserKey);
        _guardianVotes(1, newBrowserKey);
        vm.warp(block.timestamp + DELAY);

        bytes memory revoke = abi.encodeCall(IUP.setData, (_permissionsKey(ownerProxy), ""));
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, address(lsp11), "EDITPERMISSIONS"));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), revoke);

        bytes memory spend = abi.encodeCall(IUP.execute, (0, makeAddr("anywhere"), 0, ""));
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, address(lsp11), "CALL"));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), spend);

        assertEq(owner.getData(_permissionsKey(ownerProxy)), abi.encodePacked(OWNER_KEY_PERMISSIONS));
    }

    function test_noGuardiansNoRecovery() public {
        _grantLsp11Only();
        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        vm.expectRevert(AccountNotSetupYet.selector);
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);
    }

    function test_ownerRemovesAGuardian() public {
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        _ownerPasskeyCalls(
            address(lsp11), abi.encodeCall(LSP11SocialRecovery.removeGuardian, (address(owner), address(guardianUP[2])))
        );
        assertEq(lsp11.getGuardiansOf(address(owner)).length, 2);
        assertFalse(lsp11.isGuardianOf(address(owner), address(guardianUP[2])));

        vm.expectRevert(abi.encodeWithSelector(GuardianNumberCannotGoBelowThreshold.selector, address(owner), 2));
        this.ownerPasskeyCallsExternal(
            address(lsp11), abi.encodeCall(LSP11SocialRecovery.removeGuardian, (address(owner), address(guardianUP[1])))
        );
    }

    function test_decidedDefaults_twoOfThreeAnd48Hours() public {
        uint256 delay48h = 48 hours;
        _ownerEnrolsGuardians(2, delay48h);
        _guardianVotes(0, newBrowserKey);
        uint256 firstVoteAt = lsp11.getFirstRecoveryTimestampOf(address(owner), 0);
        assertGt(firstVoteAt, 0);
        vm.warp(firstVoteAt + 6 hours);
        _guardianVotes(2, newBrowserKey);

        vm.warp(firstVoteAt + delay48h - 1);
        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(CannotRecoverBeforeDelay.selector, address(owner), delay48h));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);

        vm.warp(firstVoteAt + delay48h);
        _recoverViaRelay(newBrowserKey, NEW_BROWSER_PK, _enrolmentPayload(newBrowserKey));
        assertEq(owner.getData(_permissionsKey(newBrowserKey)), abi.encodePacked(OWNER_KEY_PERMISSIONS));
    }

    function test_ownerChangesTheThreshold() public {
        _ownerEnrolsGuardians(2, DELAY);
        _ownerPasskeyCalls(address(lsp11), abi.encodeCall(LSP11SocialRecovery.setGuardiansThreshold, (address(owner), 3)));
        assertEq(lsp11.getGuardiansThresholdOf(address(owner)), 3);

        _guardianVotes(0, newBrowserKey);
        _guardianVotes(1, newBrowserKey);
        vm.warp(block.timestamp + DELAY);
        bytes memory payload = _enrolmentPayload(newBrowserKey);
        vm.prank(newBrowserKey);
        vm.expectRevert(abi.encodeWithSelector(CallerVotesHaveNotReachedThreshold.selector, address(owner), newBrowserKey));
        lsp11.recoverAccess(address(owner), newBrowserKey, bytes32(0), bytes32(0), payload);

        _guardianVotes(2, newBrowserKey);
        _recoverViaRelay(newBrowserKey, NEW_BROWSER_PK, _enrolmentPayload(newBrowserKey));
        assertEq(owner.getData(_permissionsKey(newBrowserKey)), abi.encodePacked(OWNER_KEY_PERMISSIONS));

        vm.expectRevert();
        this.ownerPasskeyCallsExternal(
            address(lsp11), abi.encodeCall(LSP11SocialRecovery.setGuardiansThreshold, (address(owner), 4))
        );
    }

    function test_guardianStepsDownAndIsReplacedInOneBatch() public {
        _ownerEnrolsGuardians(2, DELAY);
        _ownerPasskeyCalls(address(lsp11), abi.encodeCall(LSP11SocialRecovery.removeGuardian, (address(owner), address(guardianUP[2]))));

        address replacement = makeAddr("replacement-colleague-profile");
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(LSP11SocialRecovery.addGuardian, (address(owner), replacement));
        calls[1] = abi.encodeCall(LSP11SocialRecovery.removeGuardian, (address(owner), address(guardianUP[1])));
        _ownerPasskeyCalls(address(lsp11), abi.encodeCall(LSP11SocialRecovery.batchCalls, (calls)));

        assertFalse(lsp11.isGuardianOf(address(owner), address(guardianUP[1])));
        assertTrue(lsp11.isGuardianOf(address(owner), replacement));
        assertEq(lsp11.getGuardiansOf(address(owner)).length, 2);

        bytes memory vote = abi.encodeCall(LSP11SocialRecovery.voteForRecovery, (address(owner), address(guardianUP[1]), newBrowserKey));
        WebAuthn.Assertion memory a =
            _execAssertion(address(guardianUP[1]), _guardianCred(1), guardianNonce[1]++, address(lsp11), vote, guardianPasskey[1]);
        vm.prank(relayer);
        vm.expectRevert();
        WebAuthnSignerProxy(guardianProxy[1]).executeUP(0, address(lsp11), 0, vote, a);
    }

    function test_isTheVersionWeDesignedFor() public view {
        assertEq(LSP11_VERSION, 11);
        assertTrue(lsp11.supportsInterface(_INTERFACEID_LSP11));
    }

    function test_gasOfEachStep() public {
        uint256 g = gasleft();
        _ownerEnrolsGuardians(THRESHOLD, DELAY);
        console.log("setup: grant + 3 guardians + threshold + delay (2 txs):", g - gasleft());

        for (uint256 i; i < 2; i++) {
            bytes memory vote =
                abi.encodeCall(LSP11SocialRecovery.voteForRecovery, (address(owner), address(guardianUP[i]), newBrowserKey));
            WebAuthn.Assertion memory a = _execAssertion(
                address(guardianUP[i]), _guardianCred(i), guardianNonce[i]++, address(lsp11), vote, guardianPasskey[i]
            );
            vm.prank(relayer);
            g = gasleft();
            WebAuthnSignerProxy(guardianProxy[i]).executeUP(0, address(lsp11), 0, vote, a);
            console.log("guardian vote via passkey proxy (precompile), #", i + 1, g - gasleft());
        }

        vm.warp(block.timestamp + DELAY);
        bytes memory payload = _enrolmentPayload(newBrowserKey);
        g = gasleft();
        _recoverViaRelay(newBrowserKey, NEW_BROWSER_PK, payload);
        console.log("recoverAccess via LSP11 relay (ECDSA)               :", g - gasleft());

        _guardianVotes(2, makeAddr("next-round"));
        bytes memory cancel = abi.encodeCall(LSP11SocialRecovery.cancelRecoveryProcess, (address(owner)));
        WebAuthn.Assertion memory c =
            _execAssertion(address(owner), OWNER_CRED, ownerProxyNonce++, address(lsp11), cancel, OWNER_PASSKEY);
        vm.prank(relayer);
        g = gasleft();
        WebAuthnSignerProxy(ownerProxy).executeUP(0, address(lsp11), 0, cancel, c);
        console.log("cancel via owner's passkey proxy (precompile)       :", g - gasleft());
    }

    function _ownerEnrolsGuardians(uint256 threshold, uint256 delay) internal {
        _grantLsp11Only();

        bytes[] memory calls = new bytes[](N_GUARDIANS + 2);
        for (uint256 i; i < N_GUARDIANS; i++) {
            calls[i] = abi.encodeCall(LSP11SocialRecovery.addGuardian, (address(owner), address(guardianUP[i])));
        }
        calls[N_GUARDIANS] = abi.encodeCall(LSP11SocialRecovery.setGuardiansThreshold, (address(owner), threshold));
        calls[N_GUARDIANS + 1] = abi.encodeCall(LSP11SocialRecovery.setRecoveryDelay, (address(owner), delay));
        vm.prank(lostBrowserKey);
        ownerKM.execute(
            abi.encodeCall(IUP.execute, (0, address(lsp11), 0, abi.encodeCall(LSP11SocialRecovery.batchCalls, (calls))))
        );

        assertEq(lsp11.getGuardiansOf(address(owner)).length, N_GUARDIANS);
        assertEq(lsp11.getGuardiansThresholdOf(address(owner)), threshold);
        assertEq(lsp11.getRecoveryDelayOf(address(owner)), delay);
    }

    function _grantLsp11Only() internal {
        bytes32[] memory keys = new bytes32[](3);
        bytes[] memory values = new bytes[](3);
        keys[0] = _permissionsKey(address(lsp11));
        values[0] = abi.encodePacked(_PERMISSION_ADDCONTROLLER);
        keys[1] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        values[1] = abi.encodePacked(uint128(4));
        keys[2] = _arrayIndexKey(3);
        values[2] = abi.encodePacked(address(lsp11));
        vm.prank(lostBrowserKey);
        ownerKM.execute(_setDataBatchCalldata(keys, values));
    }

    function _guardianVotes(uint256 i, address voted) internal {
        bytes memory data =
            abi.encodeCall(LSP11SocialRecovery.voteForRecovery, (address(owner), address(guardianUP[i]), voted));
        WebAuthn.Assertion memory a = _execAssertion(
            address(guardianUP[i]), _guardianCred(i), guardianNonce[i]++, address(lsp11), data, guardianPasskey[i]
        );
        vm.prank(relayer);
        WebAuthnSignerProxy(guardianProxy[i]).executeUP(0, address(lsp11), 0, data, a);
        assertEq(lsp11.getVotedAddressByGuardian(address(owner), lsp11.getRecoveryCounterOf(address(owner)), address(guardianUP[i])), voted);
    }

    function _ownerPasskeyCalls(address target, bytes memory data) internal {
        WebAuthn.Assertion memory a =
            _execAssertion(address(owner), OWNER_CRED, ownerProxyNonce++, target, data, OWNER_PASSKEY);
        vm.prank(relayer);
        WebAuthnSignerProxy(ownerProxy).executeUP(0, target, 0, data, a);
    }

    function ownerPasskeyCallsExternal(address target, bytes memory data) external {
        _ownerPasskeyCalls(target, data);
    }

    function _recoverViaRelay(address voted, uint256 votedPk, bytes memory calldataToExecute) internal {
        bytes memory payload = abi.encodeCall(
            LSP11SocialRecovery.recoverAccess, (address(owner), voted, bytes32(0), bytes32(0), calldataToExecute)
        );
        uint256 nonce = lsp11.getNonce(voted, 0);
        uint256 counter = lsp11.getRecoveryCounterOf(address(owner));
        bytes memory message = abi.encodePacked(LSP11_VERSION, block.chainid, nonce, uint256(0), uint256(0), counter, payload);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x00), address(lsp11), message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(votedPk, hash);
        vm.prank(relayer);
        lsp11.executeRelayCall(abi.encodePacked(r, s, v), nonce, 0, payload);
    }

    function _execAssertion(address profile, bytes32 cred, uint256 nonce, address target, bytes memory data, uint256 pk)
        internal
        view
        returns (WebAuthn.Assertion memory)
    {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(webauthn), profile, cred, nonce,
                uint256(0), target, uint256(0), keccak256(data)
            )
        );
        return WebAuthnFixture.make(digest, pk);
    }

    function _enrolmentPayload(address who) internal view returns (bytes memory) {
        (bytes32[] memory keys, bytes[] memory values) = _enrolmentKeysValues(who);
        return _setDataBatchCalldata(keys, values);
    }

    function _enrolmentKeysValues(address who) internal view returns (bytes32[] memory keys, bytes[] memory values) {
        uint128 length = uint128(bytes16(owner.getData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY)));
        keys = new bytes32[](3);
        values = new bytes[](3);
        keys[0] = _permissionsKey(who);
        values[0] = abi.encodePacked(OWNER_KEY_PERMISSIONS);
        keys[1] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        values[1] = abi.encodePacked(length + 1);
        keys[2] = _arrayIndexKey(length);
        values[2] = abi.encodePacked(who);
    }

    function _setDataBatchCalldata(bytes32[] memory keys, bytes[] memory values) internal pure returns (bytes memory) {
        return abi.encodeCall(IUP.setDataBatch, (keys, values));
    }

    function _enrolPasskey(address profile, bytes32 cred, uint256 pk) internal returns (address proxy) {
        (uint256 x, uint256 y) = P256Signer.publicKey(pk);
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(webauthn), profile, cred, x, y,
                uint256(0)
            )
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, pk);
        vm.prank(profile);
        webauthn.registerCredential(profile, cred, x, y, a);
        proxy = webauthn.deploySignerProxy(profile, cred);
    }

    function _grant(LSP0ERC725Account up, address who, bytes32 permissions, uint128 index) internal {
        up.setData(_permissionsKey(who), abi.encodePacked(permissions));
        up.setData(_arrayIndexKey(index), abi.encodePacked(who));
    }

    function _handOver(LSP0ERC725Account up, LSP6KeyManager km) internal {
        up.transferOwnership(address(km));
        vm.prank(address(km));
        up.acceptOwnership();
    }

    function _permissionsKey(address who) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(PERMISSIONS_PREFIX, bytes2(0), who));
    }

    function _arrayIndexKey(uint128 index) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX, index));
    }
}
