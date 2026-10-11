// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {P256FallbackVerifier} from "../src/P256FallbackVerifier.sol";
import {DeployPasskeyAndV3Stack} from "../script/DeployPasskeyAndV3Stack.s.sol";
import {DeployP256FallbackVerifier} from "../script/DeployP256FallbackVerifier.s.sol";
import {IControllerProbe} from "../script/lib/P256DeployGate.sol";

contract StackScriptHarness is DeployPasskeyAndV3Stack {
    bytes internal rpcAnswer;

    function setRpcAnswer(bytes memory answer) external {
        rpcAnswer = answer;
    }

    function _rpc(string memory, string memory) internal view override returns (bytes memory) {
        return rpcAnswer;
    }

    function refuseAPrivateKeyInTheEnvironment(bool present) external pure {
        _refuseAPrivateKeyInTheEnvironment(present);
    }

    function requireSenderIsTheDeployer(address sender, address expected) external pure {
        _requireSenderIsTheDeployer(sender, expected);
    }

    function preflight(address deployer, uint256 start, uint256 offset, string memory label)
        external
        view
        returns (address predicted, bool deployed)
    {
        Plan memory plan;
        plan.deployer = deployer;
        plan.start = start;
        return _preflight(plan, offset, label);
    }

    function liveChainHasP256Precompile() external returns (bool) {
        return _liveChainHasP256Precompile();
    }

    function requireLiveP256Path(address fallbackVerifier) external returns (bool) {
        return _requireLiveP256Path(fallbackVerifier);
    }

    function requireControllerMatchesTheChain(address controller, bool live) external {
        _requireControllerMatchesTheChain(controller, live);
    }

    function scriptVmHasP256Precompile() external view returns (bool) {
        return _scriptVmHasP256Precompile();
    }

    function rpcQuantity(address account) external returns (uint256) {
        return _rpcQuantity("eth_getTransactionCount", account);
    }

    function probe() external pure returns (bytes32 h, uint256 r, uint256 s, uint256 x, uint256 y) {
        return (PROBE_HASH, PROBE_R, PROBE_S, PROBE_PUB_X, PROBE_PUB_Y);
    }
}

contract ProbeOnlyVerifier is IP256Verifier {
    bytes32 internal immutable h;
    uint256 internal immutable r;
    uint256 internal immutable s;
    uint256 internal immutable x;
    uint256 internal immutable y;

    constructor(bytes32 h_, uint256 r_, uint256 s_, uint256 x_, uint256 y_) {
        (h, r, s, x, y) = (h_, r_, s_, x_, y_);
    }

    function verify(bytes32 h_, uint256 r_, uint256 s_, uint256 x_, uint256 y_) external view returns (bool) {
        return h_ == h && r_ == r && s_ == s && x_ == x && y_ == y;
    }
}

contract AcceptsEverythingVerifier is IP256Verifier {
    function verify(bytes32, uint256, uint256, uint256, uint256) external pure returns (bool) {
        return true;
    }
}

contract RejectsEverythingVerifier is IP256Verifier {
    function verify(bytes32, uint256, uint256, uint256, uint256) external pure returns (bool) {
        return false;
    }
}

contract ControllerThatBelievesInThePrecompile {
    address public immutable p256Fallback;
    address public immutable signerImplementation;

    constructor(address fallback_, address implementation_) {
        (p256Fallback, signerImplementation) = (fallback_, implementation_);
    }

    function precompileAvailable() external pure returns (bool) {
        return true;
    }

    function supportsP256() external pure returns (bool) {
        return true;
    }
}

contract FakeController {
    bool public precompileAvailable;
    bool public supportsP256;

    constructor(bool precompileAvailable_, bool supportsP256_) {
        precompileAvailable = precompileAvailable_;
        supportsP256 = supportsP256_;
    }
}

contract DeployGateRefusalsTest is Test {
    address internal constant DEPLOYER = 0x7B38Aff77Db05f3cc51e0c23c689792509BEa97c;

    StackScriptHarness internal harness;

    function setUp() public {
        harness = new StackScriptHarness();
    }

    function _probeOnly() internal returns (address) {
        (bytes32 h, uint256 r, uint256 s, uint256 x, uint256 y) = harness.probe();
        return address(new ProbeOnlyVerifier(h, r, s, x, y));
    }

    function _chainHasNoPrecompile() internal {
        harness.setRpcAnswer(bytes(""));
    }

    function _chainHasThePrecompile() internal {
        harness.setRpcAnswer(abi.encode(uint256(1)));
    }

    function testRefusesAPrivateKeyInTheEnvironment() public {
        vm.expectRevert(
            bytes(
                "pre-flight REFUSED: PRIVATE_KEY is set in the environment. Remove it and sign with --sender <EXPECTED_DEPLOYER> --interactives 1. NEVER PASS --private-key ON THE COMMAND LINE."
            )
        );
        harness.refuseAPrivateKeyInTheEnvironment(true);
    }

    function testAcceptsNoPrivateKeyInTheEnvironment() public view {
        harness.refuseAPrivateKeyInTheEnvironment(false);
    }

    function testMissingSenderIsNamedAsMissingNotAsAWrongKey() public {
        vm.expectRevert(
            bytes(
                "pre-flight REFUSED: --sender IS MISSING. forge is running as its default caller 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38, not the deployer. This is NOT a wrong key. Add --sender <EXPECTED_DEPLOYER> next to --interactives 1. NEVER PASS --private-key ON THE COMMAND LINE: POWERSHELL SAVES IT TO DISK."
            )
        );
        harness.requireSenderIsTheDeployer(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38, DEPLOYER);
    }

    function testRefusesASenderThatIsNotTheExpectedDeployer() public {
        vm.expectRevert(
            bytes(
                "pre-flight REFUSED: --sender does not equal EXPECTED_DEPLOYER. One of the two is mistyped; fix the address, this is not the key. A wrong key is refused later by forge (No associated wallet). NEVER PASS --private-key ON THE COMMAND LINE: POWERSHELL SAVES IT TO DISK."
            )
        );

        harness.requireSenderIsTheDeployer(address(uint160(DEPLOYER) ^ 1), DEPLOYER);
    }

    function testAcceptsTheSenderThatIsTheExpectedDeployer() public view {
        harness.requireSenderIsTheDeployer(DEPLOYER, DEPLOYER);
    }

    function _nonceMessage(uint256 planned, address predicted, uint256 actual) internal pure returns (bytes memory) {
        return bytes(
            string.concat(
                "pre-flight REFUSED: WebAuthnSignerProxy is planned for nonce ",
                vm.toString(planned),
                " at ",
                vm.toString(predicted),
                " but the deployer's nonce is ",
                vm.toString(actual),
                ". Deploying now would put it at a different address. Stop and re-plan."
            )
        );
    }

    function testPreflightRefusesANonceAboveThePlan() public {
        vm.setNonce(DEPLOYER, 3);
        vm.expectRevert(_nonceMessage(2, vm.computeCreateAddress(DEPLOYER, 2), 3));
        harness.preflight(DEPLOYER, 0, 2, "WebAuthnSignerProxy");
    }

    function testPreflightRefusesANonceBelowThePlan() public {
        vm.setNonce(DEPLOYER, 1);
        vm.expectRevert(_nonceMessage(2, vm.computeCreateAddress(DEPLOYER, 2), 1));
        harness.preflight(DEPLOYER, 0, 2, "WebAuthnSignerProxy");
    }

    function testPreflightRefusesWhenTheStartNonceIsWrong() public {

        vm.setNonce(DEPLOYER, 2);
        vm.expectRevert(_nonceMessage(3, vm.computeCreateAddress(DEPLOYER, 3), 2));
        harness.preflight(DEPLOYER, 1, 2, "WebAuthnSignerProxy");
    }

    function testPreflightDeploysAtExactlyThePlannedNonce() public {
        vm.setNonce(DEPLOYER, 2);
        (address predicted, bool deployed) = harness.preflight(DEPLOYER, 0, 2, "WebAuthnSignerProxy");
        assertEq(predicted, vm.computeCreateAddress(DEPLOYER, 2));
        assertFalse(deployed);
    }

    function testPreflightSkipsAStepWhoseCodeIsAlreadyThere() public {
        address predicted = vm.computeCreateAddress(DEPLOYER, 2);
        vm.etch(predicted, hex"00");
        vm.setNonce(DEPLOYER, 5);
        (address got, bool deployed) = harness.preflight(DEPLOYER, 0, 2, "WebAuthnSignerProxy");
        assertEq(got, predicted);
        assertTrue(deployed);
    }

    function testLiveAnswerIsReadFromTheRpcNotTheScriptEvm() public {

        assertTrue(harness.scriptVmHasP256Precompile());
        _chainHasNoPrecompile();
        assertFalse(harness.liveChainHasP256Precompile());
        _chainHasThePrecompile();
        assertTrue(harness.liveChainHasP256Precompile());
        harness.setRpcAnswer(abi.encode(uint256(2)));
        assertFalse(harness.liveChainHasP256Precompile());
    }

    function testRpcQuantityDecodesAMinimalBigEndianQuantity() public {
        harness.setRpcAnswer(hex"0102");
        assertEq(harness.rpcQuantity(DEPLOYER), 0x0102);
    }

    function testGateRefusesAMissingFallbackWhenTheChainHasNoPrecompile() public {
        _chainHasNoPrecompile();
        vm.expectRevert(
            bytes("P256 gate REFUSED: the live chain has no RIP-7212 precompile and P256_FALLBACK_VERIFIER is unset")
        );
        harness.requireLiveP256Path(address(0));
    }

    function testGateAllowsAMissingFallbackOnlyWhenTheChainHasThePrecompile() public {
        _chainHasThePrecompile();
        assertTrue(harness.requireLiveP256Path(address(0)));
    }

    function testGateRefusesAFallbackAddressWithNoCode() public {
        _chainHasNoPrecompile();
        vm.expectRevert(
            bytes("P256 gate REFUSED: no code at P256_FALLBACK_VERIFIER on this chain (deploy the verifier first)")
        );
        harness.requireLiveP256Path(address(0xBEEF));
    }

    function testGateRefusesAVerifierThatRejectsTheProbe() public {
        _chainHasNoPrecompile();
        address rejecting = address(new RejectsEverythingVerifier());
        vm.expectRevert(bytes("P256 gate REFUSED: P256_FALLBACK_VERIFIER rejects the known-valid probe vector"));
        harness.requireLiveP256Path(rejecting);
    }

    function testGateRefusesAVerifierThatAcceptsACorruptedSignature() public {
        _chainHasNoPrecompile();
        address impostor = address(new AcceptsEverythingVerifier());
        vm.expectRevert(bytes("P256 gate REFUSED: P256_FALLBACK_VERIFIER accepts a corrupted signature"));
        harness.requireLiveP256Path(impostor);
    }

    function testGatePassesAnHonestVerifierOnAChainWithoutThePrecompile() public {
        _chainHasNoPrecompile();
        assertFalse(harness.requireLiveP256Path(_probeOnly()));
    }

    function testGatePassesTheRealLinkedFallbackVerifier() public {
        _chainHasNoPrecompile();
        assertFalse(harness.requireLiveP256Path(address(new P256FallbackVerifier())));
    }

    function testGateRefusesAControllerThatDisagreesWithTheLiveChain() public {

        address controller = address(new FakeController(true, true));
        vm.expectRevert(
            bytes("P256 gate REFUSED: the simulated controller disagrees with the live chain about the precompile")
        );
        harness.requireControllerMatchesTheChain(controller, false);
    }

    function testGateRefusesAControllerThatCannotVerifyByAnyPath() public {
        address controller = address(new FakeController(false, false));
        vm.expectRevert(bytes("P256 gate REFUSED: the controller cannot verify P-256 by ANY path on this chain"));
        harness.requireControllerMatchesTheChain(controller, false);
    }

    function testGatePassesAControllerThatMatchesTheChainAndVerifies() public {
        harness.requireControllerMatchesTheChain(address(new FakeController(false, true)), false);
    }

    function testDeployP256FallbackVerifierRefusesChain42() public {
        DeployP256FallbackVerifier script = new DeployP256FallbackVerifier();
        vm.chainId(42);
        vm.expectRevert(
            bytes("chain 42: use script/DeployPasskeyAndV3Stack.s.sol, which pre-flights nonces and skips deployed steps")
        );
        script.run();
    }
}

contract DeployStackRunRefusalsTest is Test, DeployPasskeyAndV3Stack {
    address internal constant FORGE_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address internal constant SOMEONE_ELSE = 0x7B38Aff77Db05f3cc51e0c23c689792509BEa97c;

    bytes internal rpcAnswer;
    bool internal privateKeyPresent;
    address internal expectedDeployerAnswer;
    uint256 internal startNonceAnswer;

    function _rpc(string memory, string memory) internal view override returns (bytes memory) {
        return rpcAnswer;
    }

    function _privateKeyInEnvironment() internal view override returns (bool) {
        return privateKeyPresent;
    }

    function _expectedDeployer() internal view override returns (address) {
        return expectedDeployerAnswer;
    }

    function _deployStartNonce() internal view override returns (uint256) {
        return startNonceAnswer;
    }

    function _libraryAddress() internal view returns (address) {
        return vm.computeCreate2Address(LIBRARY_CREATE2_SALT, keccak256(vm.getCode(LIBRARY_ARTIFACT)), CREATE2_DEPLOYER);
    }

    function _arrangeAFreshSigningRun() internal returns (uint256 start) {
        start = vm.getNonce(FORGE_DEFAULT_SENDER);
        vm.etch(_libraryAddress(), vm.getDeployedCode(LIBRARY_ARTIFACT));
        vm.setNonce(FORGE_DEFAULT_SENDER, uint64(start + 1));
        (privateKeyPresent, expectedDeployerAnswer, startNonceAnswer) = (false, FORGE_DEFAULT_SENDER, start);
        rpcAnswer = bytes("");
    }

    function _runExpectingRefusal(bytes memory message) internal {
        vm.prank(FORGE_DEFAULT_SENDER);
        vm.expectRevert(message);
        this.run();
    }

    function testRunDeploysAllFiveAtThePlannedAddressesAsChain42WillBuildThem() public {
        assertEq(msg.sender, FORGE_DEFAULT_SENDER, "positive control: the test's caller is forge's default caller");
        uint256 start = _arrangeAFreshSigningRun();
        (address verifier, address proxy, address controller, address factory) = run();

        assertEq(verifier, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 1), "verifier address");
        assertEq(proxy, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 2), "proxy address");
        assertEq(controller, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 3), "controller address");
        assertEq(factory, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 4), "factory address");
        assertEq(vm.getNonce(FORGE_DEFAULT_SENDER), start + 5, "four CREATEs after the library, no more");

        assertTrue(_scriptVmHasP256Precompile(), "positive control: this executor has 0x100");
        assertFalse(IControllerProbe(controller).precompileAvailable(), "controller built as chain 42 will build it");
        assertEq(IControllerProbe(controller).p256Fallback(), verifier, "controller wired to the planned verifier");
        assertEq(IControllerProbe(controller).signerImplementation(), proxy, "controller wired to the planned proxy");
    }

    function testRunRefusesAPrivateKeyInTheEnvironment() public {
        _arrangeAFreshSigningRun();
        privateKeyPresent = true;
        _runExpectingRefusal(
            bytes(
                "pre-flight REFUSED: PRIVATE_KEY is set in the environment. Remove it and sign with --sender <EXPECTED_DEPLOYER> --interactives 1. NEVER PASS --private-key ON THE COMMAND LINE."
            )
        );
    }

    function testRunRefusesAMissingSender() public {
        _arrangeAFreshSigningRun();
        expectedDeployerAnswer = SOMEONE_ELSE;
        _runExpectingRefusal(
            bytes(
                "pre-flight REFUSED: --sender IS MISSING. forge is running as its default caller 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38, not the deployer. This is NOT a wrong key. Add --sender <EXPECTED_DEPLOYER> next to --interactives 1. NEVER PASS --private-key ON THE COMMAND LINE: POWERSHELL SAVES IT TO DISK."
            )
        );
    }

    function testRunRefusesASenderThatIsNotTheExpectedDeployer() public {
        _arrangeAFreshSigningRun();
        expectedDeployerAnswer = SOMEONE_ELSE;
        vm.prank(address(uint160(SOMEONE_ELSE) ^ 1));
        vm.expectRevert(
            bytes(
                "pre-flight REFUSED: --sender does not equal EXPECTED_DEPLOYER. One of the two is mistyped; fix the address, this is not the key. A wrong key is refused later by forge (No associated wallet). NEVER PASS --private-key ON THE COMMAND LINE: POWERSHELL SAVES IT TO DISK."
            )
        );
        this.run();
    }

    function testRunRefusesWhenForgeDidNotPlaceTheLibrary() public {
        uint256 start = _arrangeAFreshSigningRun();
        vm.etch(_libraryAddress(), bytes(""));
        assertEq(start, startNonceAnswer);
        _runExpectingRefusal(bytes("pre-flight REFUSED: forge did not place SCL_RIP7212 at its predicted CREATE2 address"));
    }

    function testRunRefusesANonceThatIsNotThePlan() public {
        uint256 start = _arrangeAFreshSigningRun();
        vm.setNonce(FORGE_DEFAULT_SENDER, uint64(start + 2));
        _runExpectingRefusal(
            bytes(
                string.concat(
                    "pre-flight REFUSED: P256FallbackVerifier is planned for nonce ",
                    vm.toString(start + 1),
                    " at ",
                    vm.toString(vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 1)),
                    " but the deployer's nonce is ",
                    vm.toString(start + 2),
                    ". Deploying now would put it at a different address. Stop and re-plan."
                )
            )
        );
    }

    function testRunRefusesAnImpostorAlreadyAtTheVerifiersAddress() public {
        uint256 start = _arrangeAFreshSigningRun();
        vm.etch(vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 1), address(new AcceptsEverythingVerifier()).code);
        _runExpectingRefusal(bytes("P256 gate REFUSED: P256_FALLBACK_VERIFIER accepts a corrupted signature"));
    }

    function testRunRefusesAControllerThatDisagreesWithTheLiveChainOnAReRun() public {
        _arrangeAFreshSigningRun();
        (address verifier, address proxy, address controller,) = run();
        vm.etch(controller, address(new ControllerThatBelievesInThePrecompile(verifier, proxy)).code);
        _runExpectingRefusal(
            bytes("P256 gate REFUSED: the simulated controller disagrees with the live chain about the precompile")
        );
    }
}
