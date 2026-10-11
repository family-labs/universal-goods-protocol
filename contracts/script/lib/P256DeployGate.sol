// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {IP256Verifier} from "../../src/IP256Verifier.sol";

abstract contract P256DeployGate is Script {

    address internal constant P256_PRECOMPILE = 0x0000000000000000000000000000000000000100;

    uint256 internal constant LUKSO_MAINNET_CHAIN_ID = 42;

    bytes32 internal constant PROBE_HASH =
        0x68418a5367430a8cec56ab6a11907ba494034850f5d5065128fdc3cac0ecd183;
    uint256 internal constant PROBE_R =
        0x748f1832e2aa98358d9afa7debc3766fcf99725fbc7603ee39e60ae17ae17e86;
    uint256 internal constant PROBE_S =
        0x5c7a973262dc6f9665ffece327b9616015910f305e5300cb3910d960ab83342e;
    uint256 internal constant PROBE_PUB_X =
        0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 internal constant PROBE_PUB_Y =
        0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    function _probeCalldata() internal pure returns (bytes memory) {
        return abi.encodePacked(PROBE_HASH, PROBE_R, PROBE_S, PROBE_PUB_X, PROBE_PUB_Y);
    }

    function _liveChainHasP256Precompile() internal returns (bool) {
        string memory params = string.concat(
            '[{"to":"', vm.toString(P256_PRECOMPILE), '","data":"', vm.toString(_probeCalldata()), '"},"latest"]'
        );
        bytes memory result = _rpc("eth_call", params);
        return result.length == 32 && abi.decode(result, (uint256)) == 1;
    }

    function _rpc(string memory method, string memory params) internal virtual returns (bytes memory) {
        return vm.rpc(method, params);
    }

    function _scriptVmHasP256Precompile() internal view returns (bool) {
        (bool ok, bytes memory result) = P256_PRECOMPILE.staticcall(_probeCalldata());
        return ok && result.length == 32 && abi.decode(result, (uint256)) == 1;
    }

    function _requireWorkingP256Verifier(address verifier) internal view {
        require(
            verifier.code.length != 0,
            "P256 gate REFUSED: no code at P256_FALLBACK_VERIFIER on this chain (deploy the verifier first)"
        );
        require(
            IP256Verifier(verifier).verify(PROBE_HASH, PROBE_R, PROBE_S, PROBE_PUB_X, PROBE_PUB_Y),
            "P256 gate REFUSED: P256_FALLBACK_VERIFIER rejects the known-valid probe vector"
        );
        require(
            !IP256Verifier(verifier).verify(PROBE_HASH, PROBE_R, PROBE_S ^ 1, PROBE_PUB_X, PROBE_PUB_Y),
            "P256 gate REFUSED: P256_FALLBACK_VERIFIER accepts a corrupted signature"
        );
    }

    function _requireLiveP256Path(address fallbackVerifier) internal returns (bool live) {
        live = _liveChainHasP256Precompile();
        bool inVm = _scriptVmHasP256Precompile();

        console.log("RIP-7212 precompile on the LIVE chain (eth_call over --rpc-url):", live);
        console.log("RIP-7212 precompile in this script's own EVM (evm_version):    ", inVm);
        if (live != inVm) {
            console.log("  ! the script EVM disagrees with the chain; the LIVE answer governs this gate");
        }

        require(
            fallbackVerifier != address(0) || live,
            "P256 gate REFUSED: the live chain has no RIP-7212 precompile and P256_FALLBACK_VERIFIER is unset"
        );
        if (fallbackVerifier != address(0)) {
            _requireWorkingP256Verifier(fallbackVerifier);
            console.log("P256 fallback verifier accepts the probe and rejects a corruption:", fallbackVerifier);
        }
        console.log(
            live
                ? "  -> the chain verifies via the precompile; the fallback is deployed but unused."
                : "  -> NO precompile on the chain; the controller will verify via the pure-Solidity fallback."
        );
    }

    function _simulateTheLiveChainsPrecompile(bool live) internal {
        if (!live) vm.mockCall(P256_PRECOMPILE, bytes(""), bytes(""));
    }

    function _requireControllerMatchesTheChain(address controller, bool live) internal {
        bool fixedAtConstruction = IControllerProbe(controller).precompileAvailable();
        console.log("controller.precompileAvailable() as the chain will compute it:", fixedAtConstruction);
        require(
            fixedAtConstruction == live,
            "P256 gate REFUSED: the simulated controller disagrees with the live chain about the precompile"
        );
        require(
            IControllerProbe(controller).supportsP256(),
            "P256 gate REFUSED: the controller cannot verify P-256 by ANY path on this chain"
        );
        console.log("controller.supportsP256() through the chain's own path: true");
        vm.clearMockedCalls();
    }
}

interface IControllerProbe {
    function precompileAvailable() external view returns (bool);
    function supportsP256() external view returns (bool);
    function p256Fallback() external view returns (address);
    function signerImplementation() external view returns (address);
}
