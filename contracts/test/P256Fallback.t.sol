// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {P256FallbackVerifier} from "../src/P256FallbackVerifier.sol";
import {P256DeployGate} from "../script/lib/P256DeployGate.sol";

contract DeployGateVectorReader is P256DeployGate {
    function probe() external pure returns (bytes memory) {
        return _probeCalldata();
    }
}

contract P256Harness {
    function verify(
        bytes32 messageHash,
        uint256 r,
        uint256 s,
        uint256 x,
        uint256 y,
        bool precompileAvailable,
        IP256Verifier fallbackVerifier
    ) external view returns (bool) {
        return WebAuthn.p256Verify(
            messageHash, r, s, x, y, precompileAvailable, fallbackVerifier
        );
    }
}

contract P256FallbackTest is Test {
    P256Harness harness;
    IP256Verifier fallbackVerifier;

    bytes32 constant HASH =
        0x68418a5367430a8cec56ab6a11907ba494034850f5d5065128fdc3cac0ecd183;
    uint256 constant R = 0x748f1832e2aa98358d9afa7debc3766fcf99725fbc7603ee39e60ae17ae17e86;
    uint256 constant S = 0x5c7a973262dc6f9665ffece327b9616015910f305e5300cb3910d960ab83342e;
    uint256 constant PUB_X = 0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 constant PUB_Y = 0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    bytes32 constant GEN_HASH =
        0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
    uint256 constant GEN_R = 0x07f1a261bcf18d1ee034eb9f44ad6bdbe224fa43f186a438fe4ad9fa83a9ff233;
    uint256 constant GEN_S = 0x6477e4e3a264408106beb0f30ce1e0c9316e7f3194d38d034d7c92e2ed16593e;
    uint256 constant GEN_X = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    uint256 constant GEN_Y = 0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5;

    function setUp() public {
        harness = new P256Harness();
        fallbackVerifier = IP256Verifier(address(new P256FallbackVerifier()));
    }

    function testFallbackAndPrecompileAgreeOnAValidSignature() public view {
        assertTrue(
            harness.verify(HASH, R, S, PUB_X, PUB_Y, true, IP256Verifier(address(0))),
            "precompile must accept the known-valid vector"
        );
        assertTrue(
            harness.verify(HASH, R, S, PUB_X, PUB_Y, false, fallbackVerifier),
            "pure-Solidity fallback must accept the SAME known-valid vector"
        );
    }

    function testFallbackAndPrecompileAgreeOnACorruptedSignature() public view {
        assertFalse(
            harness.verify(HASH, R, S ^ 1, PUB_X, PUB_Y, true, IP256Verifier(address(0))),
            "precompile must reject a corrupted signature"
        );
        assertFalse(
            harness.verify(HASH, R, S ^ 1, PUB_X, PUB_Y, false, fallbackVerifier),
            "fallback must reject the same corrupted signature"
        );
        assertFalse(
            harness.verify(keccak256("other"), R, S, PUB_X, PUB_Y, false, fallbackVerifier),
            "fallback must reject a valid signature over a DIFFERENT message"
        );
    }

    function testFallbackRejectsAGeneratorPublicKeyThatThePrecompileAccepts() public view {
        assertTrue(
            harness.verify(GEN_HASH, GEN_R, GEN_S, GEN_X, GEN_Y, true, IP256Verifier(address(0))),
            "precompile ACCEPTS the generator-key vector"
        );
        assertFalse(
            harness.verify(GEN_HASH, GEN_R, GEN_S, GEN_X, GEN_Y, false, fallbackVerifier),
            "vendored fallback REJECTS the same vector - documented divergence, private key = 1"
        );
    }

    function testProbePublicKeyIsTwiceTheGenerator() public view {
        uint256 p = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff;
        uint256 a = p - 3;

        uint256 num = addmod(mulmod(3, mulmod(GEN_X, GEN_X, p), p), a, p);
        uint256 lambda = mulmod(num, _invMod(mulmod(2, GEN_Y, p), p), p);
        uint256 x2 = addmod(mulmod(lambda, lambda, p), p - mulmod(2, GEN_X, p), p);
        uint256 y2 = addmod(mulmod(lambda, addmod(GEN_X, p - x2, p), p), p - GEN_Y, p);
        assertEq(x2, PUB_X, "PUB_X must be the x-coordinate of 2G");
        assertEq(y2, PUB_Y, "PUB_Y must be the y-coordinate of 2G");
    }

    function testDeployGateProbeIsTheControllersProbe() public {
        assertEq(
            new DeployGateVectorReader().probe(),
            abi.encodePacked(HASH, R, S, PUB_X, PUB_Y),
            "script/lib/P256DeployGate.sol must probe with the private-key-2 vector"
        );
    }

    function _invMod(uint256 v, uint256 m) internal view returns (uint256) {
        (bool ok, bytes memory res) =
            address(0x05).staticcall(abi.encode(uint256(32), uint256(32), uint256(32), v, m - 2, m));
        require(ok, "modexp failed");
        return abi.decode(res, (uint256));
    }

    function testNoPrecompileAndNoFallbackRevertsLoudly() public {
        vm.expectRevert(WebAuthn.P256VerificationUnavailable.selector);
        harness.verify(HASH, R, S, PUB_X, PUB_Y, false, IP256Verifier(address(0)));
    }

    function testMeasureBothVerificationPaths() public view {
        uint256 before = gasleft();
        harness.verify(HASH, R, S, PUB_X, PUB_Y, true, IP256Verifier(address(0)));
        uint256 precompileGas = before - gasleft();

        before = gasleft();
        harness.verify(HASH, R, S, PUB_X, PUB_Y, false, fallbackVerifier);
        uint256 fallbackGas = before - gasleft();

        console.log("P256 verify via precompile        :", precompileGas);
        console.log("P256 verify via pure Solidity     :", fallbackGas);
        console.log("fallback / precompile ratio (x100):", (fallbackGas * 100) / precompileGas);
    }
}
