// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DeployWebAuthnController} from "../script/DeployWebAuthnController.s.sol";
import {DeployRealWorldAssetsV3Factory} from "../script/DeployRealWorldAssetsV3Factory.s.sol";
import {DeployWebAuthnSignerProxyFactory} from "../script/DeployWebAuthnSignerProxyFactory.s.sol";
import {WebAuthnIntegrationExample} from "../script/WebAuthnIntegrationExample.s.sol";
import {DeployAssetInfrastructure} from "../script/DeployAssetInfrastructure.s.sol";

contract ControllerScriptOnAChainWithThePrecompile is DeployWebAuthnController {
    function _rpc(string memory, string memory) internal pure override returns (bytes memory) {
        return abi.encode(uint256(1));
    }
}

contract ControllerScriptOnAChainWithoutThePrecompile is DeployWebAuthnController {
    function _rpc(string memory, string memory) internal pure override returns (bytes memory) {
        return bytes("");
    }
}

string constant MISSING_FALLBACK_REFUSAL =
    "P256 gate REFUSED: the live chain has no RIP-7212 precompile and P256_FALLBACK_VERIFIER is unset";

contract DeployWebAuthnControllerGateTest is Test {
    function testControllerRunRefusesAMissingFallbackOnAChainWithoutThePrecompile() public {
        assertFalse(vm.envExists("P256_FALLBACK_VERIFIER"), "control: P256_FALLBACK_VERIFIER must be unset");
        ControllerScriptOnAChainWithoutThePrecompile script = new ControllerScriptOnAChainWithoutThePrecompile();
        vm.chainId(4201);
        vm.expectRevert(bytes(MISSING_FALLBACK_REFUSAL));
        script.run();
    }
}

contract DeployControllerLiveRpcTest is Test {
    function testControllerScriptUnoverriddenRefusesAMissingFallbackOnARealNode() public {
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
        assertFalse(vm.envExists("P256_FALLBACK_VERIFIER"), "control: P256_FALLBACK_VERIFIER must be unset");
        assertTrue(block.chainid != 42, "control: not chain 42, so only the gate can refuse");

        DeployWebAuthnController script = new DeployWebAuthnController();
        vm.expectRevert(bytes(MISSING_FALLBACK_REFUSAL));
        script.run();
    }
}

contract DeployChain42RefusalsTest is Test {
    string internal constant USE_THE_STACK =
        "chain 42: use script/DeployPasskeyAndV3Stack.s.sol, which pre-flights nonces and skips deployed steps";

    function _expectChain42() internal {
        vm.chainId(42);
        vm.expectRevert(bytes(USE_THE_STACK));
    }

    function testDeployWebAuthnControllerRefusesChain42AfterItsGatePasses() public {
        ControllerScriptOnAChainWithThePrecompile script = new ControllerScriptOnAChainWithThePrecompile();
        _expectChain42();
        script.run();
    }

    function testDeployWebAuthnControllerDeploysOffChain42() public {
        ControllerScriptOnAChainWithThePrecompile script = new ControllerScriptOnAChainWithThePrecompile();
        vm.chainId(4201);
        (address controller,) = script.run();
        assertTrue(controller.code.length != 0);
    }

    function testDeployRealWorldAssetsV3FactoryRefusesChain42() public {
        DeployRealWorldAssetsV3Factory script = new DeployRealWorldAssetsV3Factory();
        _expectChain42();
        script.run();
    }

    function testDeployWebAuthnSignerProxyFactoryRefusesChain42() public {
        DeployWebAuthnSignerProxyFactory script = new DeployWebAuthnSignerProxyFactory();
        _expectChain42();
        script.run();
    }

    function testWebAuthnIntegrationExampleRefusesChain42() public {
        WebAuthnIntegrationExample script = new WebAuthnIntegrationExample();
        vm.chainId(42);
        vm.expectRevert(bytes("chain 42: this example has no P-256 gate; use script/DeployPasskeyAndV3Stack.s.sol"));
        script.run();
    }

    function testDeployAssetInfrastructureRefusesChain42() public {
        DeployAssetInfrastructure script = new DeployAssetInfrastructure();
        vm.chainId(42);
        vm.expectRevert(
            bytes(
                "chain 42: this script would deploy a second RealWorldAssetsV3Factory; use script/DeployPasskeyAndV3Stack.s.sol"
            )
        );
        script.run();
    }
}
