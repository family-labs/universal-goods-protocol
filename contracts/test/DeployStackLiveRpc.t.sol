// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DeployPasskeyAndV3Stack} from "../script/DeployPasskeyAndV3Stack.s.sol";
import {IControllerProbe} from "../script/lib/P256DeployGate.sol";

contract DeployStackLiveRpcTest is Test, DeployPasskeyAndV3Stack {
    address internal constant FORGE_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    function _requireALiveNodeOrSkip() internal {
        bool forked;
        try vm.activeFork() returns (uint256) {
            forked = true;
        } catch {
            forked = false;
        }
        if (!forked) {
            require(
                !vm.envOr("DEPLOY_GATE_LIVE_RPC_REQUIRED", false),
                "DEPLOY_GATE_LIVE_RPC_REQUIRED is set but forge test has no --fork-url: the live RPC path would not run"
            );
            vm.skip(true, "needs --fork-url to a node without the P-256 precompile (CI: anvil --hardfork prague)");
        }
    }

    function testStackRunUnoverriddenAgainstARealNodeWithoutThePrecompile() public {
        _requireALiveNodeOrSkip();

        bytes memory nodeAnswer = vm.rpc(
            "eth_call",
            string.concat(
                '[{"to":"', vm.toString(P256_PRECOMPILE), '","data":"', vm.toString(_probeCalldata()), '"},"latest"]'
            )
        );
        assertEq(nodeAnswer.length, 0, "control: the node behind --fork-url must LACK the precompile (anvil --hardfork prague)");
        assertTrue(_scriptVmHasP256Precompile(), "control: this executor (osaka) HAS the precompile, so the two disagree");
        assertEq(msg.sender, FORGE_DEFAULT_SENDER, "control: the test's caller is forge's default caller");
        assertFalse(vm.envExists("PRIVATE_KEY"), "control: PRIVATE_KEY must be unset for the first run");
        assertEq(vm.envAddress("EXPECTED_DEPLOYER"), FORGE_DEFAULT_SENDER, "control: EXPECTED_DEPLOYER is forge's default caller");

        uint256 start = vm.envUint("DEPLOY_START_NONCE");
        address library_ =
            vm.computeCreate2Address(LIBRARY_CREATE2_SALT, keccak256(vm.getCode(LIBRARY_ARTIFACT)), CREATE2_DEPLOYER);
        vm.etch(library_, vm.getDeployedCode(LIBRARY_ARTIFACT));
        vm.setNonce(FORGE_DEFAULT_SENDER, uint64(start + 1));

        (address verifier, address proxy, address controller, address factory) = run();

        assertEq(verifier, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 1), "verifier address");
        assertEq(proxy, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 2), "proxy address");
        assertEq(controller, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 3), "controller address");
        assertEq(factory, vm.computeCreateAddress(FORGE_DEFAULT_SENDER, start + 4), "factory address");

        assertFalse(
            IControllerProbe(controller).precompileAvailable(), "controller built as a chain without 0x100 will build it"
        );
        assertEq(IControllerProbe(controller).p256Fallback(), verifier, "controller wired to the planned verifier");

        vm.setEnv("PRIVATE_KEY", "set-by-DeployStackLiveRpcTest-not-a-key");
        vm.prank(FORGE_DEFAULT_SENDER);
        vm.expectRevert(
            bytes(
                "pre-flight REFUSED: PRIVATE_KEY is set in the environment. Remove it and sign with --sender <EXPECTED_DEPLOYER> --interactives 1. NEVER PASS --private-key ON THE COMMAND LINE."
            )
        );
        this.run();
    }
}
