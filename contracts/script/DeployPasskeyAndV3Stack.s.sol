// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {console} from "forge-std/Script.sol";
import {P256FallbackVerifier} from "../src/P256FallbackVerifier.sol";
import {P256DeployGate, IControllerProbe} from "./lib/P256DeployGate.sol";

interface IRealWorldAssetsV3FactoryRehearsal {
    function computeAddress(bytes32 salt, string memory name, string memory symbol, address owner)
        external
        view
        returns (address);
    function createRealWorldAssetsV3Deterministic(
        string memory name,
        string memory symbol,
        address owner,
        bytes32 salt
    ) external returns (address);
}

interface IOwnedCollection {
    function owner() external view returns (address);
}

contract DeployPasskeyAndV3Stack is P256DeployGate {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    bytes32 internal constant LIBRARY_CREATE2_SALT = bytes32(0);
    uint256 internal constant EIP170_LIMIT = 24_576;

    string internal constant LIBRARY_ARTIFACT = "libSCL_RIP7212.sol:SCL_RIP7212";
    string internal constant PROXY_ARTIFACT = "WebAuthnSignerProxy.sol:WebAuthnSignerProxy";
    string internal constant CONTROLLER_ARTIFACT = "WebAuthnController.sol:WebAuthnController";
    string internal constant FACTORY_ARTIFACT = "RealWorldAssetsV3Factory.sol:RealWorldAssetsV3Factory";

    struct Plan {
        address deployer;
        uint256 start;
        address library_;
        address verifier;
        address proxy;
        address controller;
        address factory;
    }

    function run()
        public
        returns (address verifier, address proxy, address controller, address factory)
    {
        Plan memory plan = _loadAndPrintPlan();
        _requireLibraryAtPlannedAddress(plan);

        verifier = _stepVerifier(plan);

        console.log("");
        console.log("== P-256 gate (asks the live chain, not the script EVM) ==");
        bool live = _requireLiveP256Path(verifier);

        console.log("");
        proxy = _stepProxy(plan);
        controller = _stepController(plan, verifier, proxy, live);
        factory = _stepFactory(plan);

        console.log("");
        console.log("== DONE. Record these in packages/network-config for chain 42 ==");
        console.log("  p256FallbackVerifier    ", verifier);
        console.log("  webAuthnSignerProxy     ", proxy);
        console.log("  webAuthnController      ", controller);
        console.log("  realWorldAssetsV3Factory", factory);
    }

    function _loadAndPrintPlan() internal returns (Plan memory plan) {
        _refuseAPrivateKeyInTheEnvironment(_privateKeyInEnvironment());
        address expected = _expectedDeployer();
        plan.start = _deployStartNonce();
        plan.deployer = msg.sender;

        console.log("== PASSKEY + V3 DEPLOY PLAN - compare every line with the PR before signing ==");
        console.log("chain id                 ", block.chainid);
        console.log("block number             ", block.number);
        console.log("signing address (forge)  ", plan.deployer);
        console.log("EXPECTED_DEPLOYER        ", expected);
        console.log("DEPLOY_START_NONCE       ", plan.start);

        console.log("deployer nonce ON CHAIN  ", _rpcQuantity("eth_getTransactionCount", plan.deployer));
        console.log("deployer balance ON CHAIN (wei)", _rpcQuantity("eth_getBalance", plan.deployer));
        console.log("deployer nonce in simulation (after forge's library tx, if any)", uint256(vm.getNonce(plan.deployer)));

        _requireSenderIsTheDeployer(plan.deployer, expected);

        plan.library_ = vm.computeCreate2Address(
            LIBRARY_CREATE2_SALT, keccak256(vm.getCode(LIBRARY_ARTIFACT)), CREATE2_DEPLOYER
        );
        plan.verifier = vm.computeCreateAddress(plan.deployer, plan.start + 1);
        plan.proxy = vm.computeCreateAddress(plan.deployer, plan.start + 2);
        plan.controller = vm.computeCreateAddress(plan.deployer, plan.start + 3);
        plan.factory = vm.computeCreateAddress(plan.deployer, plan.start + 4);

        console.log("predicted addresses:");
        console.log("  tx 1  SCL_RIP7212 library      (CREATE2)", plan.library_);
        console.log("  tx 2  P256FallbackVerifier     nonce S+1", plan.verifier);
        console.log("  tx 3  WebAuthnSignerProxy      nonce S+2", plan.proxy);
        console.log("  tx 4  WebAuthnController       nonce S+3", plan.controller);
        console.log("  tx 5  RealWorldAssetsV3Factory nonce S+4", plan.factory);
    }

    function _privateKeyInEnvironment() internal virtual returns (bool) {
        return vm.envExists("PRIVATE_KEY");
    }

    function _expectedDeployer() internal virtual returns (address) {
        return vm.envAddress("EXPECTED_DEPLOYER");
    }

    function _deployStartNonce() internal virtual returns (uint256) {
        return vm.envUint("DEPLOY_START_NONCE");
    }

    function _refuseAPrivateKeyInTheEnvironment(bool privateKeyInEnvironment) internal pure {
        require(
            !privateKeyInEnvironment,
            "pre-flight REFUSED: PRIVATE_KEY is set in the environment. Remove it and sign with --sender <EXPECTED_DEPLOYER> --interactives 1. NEVER PASS --private-key ON THE COMMAND LINE."
        );
    }

    function _requireSenderIsTheDeployer(address sender, address expected) internal pure {

        if (sender == DEFAULT_SENDER && expected != DEFAULT_SENDER) {
            revert(
                "pre-flight REFUSED: --sender IS MISSING. forge is running as its default caller 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38, not the deployer. This is NOT a wrong key. Add --sender <EXPECTED_DEPLOYER> next to --interactives 1. NEVER PASS --private-key ON THE COMMAND LINE: POWERSHELL SAVES IT TO DISK."
            );
        }
        require(
            sender == expected,
            "pre-flight REFUSED: --sender does not equal EXPECTED_DEPLOYER. One of the two is mistyped; fix the address, this is not the key. A wrong key is refused later by forge (No associated wallet). NEVER PASS --private-key ON THE COMMAND LINE: POWERSHELL SAVES IT TO DISK."
        );
    }

    function _rpcQuantity(string memory method, address account) internal returns (uint256 value) {
        bytes memory raw = _rpc(method, string.concat('["', vm.toString(account), '","latest"]'));
        require(raw.length <= 32, "unexpected RPC quantity width");
        for (uint256 i = 0; i < raw.length; i++) {
            value = (value << 8) | uint8(raw[i]);
        }
    }

    function _requireLibraryAtPlannedAddress(Plan memory plan) internal view {
        require(
            plan.library_.code.length != 0,
            "pre-flight REFUSED: forge did not place SCL_RIP7212 at its predicted CREATE2 address"
        );
    }

    function _preflight(Plan memory plan, uint256 offset, string memory label)
        internal
        view
        returns (address predicted, bool deployed)
    {
        predicted = vm.computeCreateAddress(plan.deployer, plan.start + offset);
        if (predicted.code.length != 0) {
            console.log(string.concat("  SKIP ", label, " - already deployed at"), predicted);
            return (predicted, true);
        }
        uint256 nonceNow = vm.getNonce(plan.deployer);
        if (nonceNow != plan.start + offset) {
            revert(
                string.concat(
                    "pre-flight REFUSED: ",
                    label,
                    " is planned for nonce ",
                    vm.toString(plan.start + offset),
                    " at ",
                    vm.toString(predicted),
                    " but the deployer's nonce is ",
                    vm.toString(nonceNow),
                    ". Deploying now would put it at a different address. Stop and re-plan."
                )
            );
        }
        console.log(string.concat("  DEPLOY ", label, " at nonce ", vm.toString(nonceNow), " ->"), predicted);
    }

    function _requireLanded(address actual, address predicted, string memory label) internal pure {
        require(actual == predicted, string.concat("post-flight REFUSED: ", label, " did not land at its predicted address"));
    }

    function _stepVerifier(Plan memory plan) internal returns (address verifier) {
        bool deployed;
        (verifier, deployed) = _preflight(plan, 1, "P256FallbackVerifier");
        if (deployed) return verifier;
        vm.startBroadcast();
        address actual = address(new P256FallbackVerifier());
        vm.stopBroadcast();
        _requireLanded(actual, verifier, "P256FallbackVerifier");
    }

    function _stepProxy(Plan memory plan) internal returns (address proxy) {
        bool deployed;
        (proxy, deployed) = _preflight(plan, 2, "WebAuthnSignerProxy");
        if (!deployed) {
            vm.startBroadcast();
            address actual = vm.deployCode(PROXY_ARTIFACT);
            vm.stopBroadcast();
            _requireLanded(actual, proxy, "WebAuthnSignerProxy");
        }
        require(
            keccak256(proxy.code) == keccak256(vm.getDeployedCode(PROXY_ARTIFACT)),
            "identity REFUSED: the code at the proxy address is not this build's WebAuthnSignerProxy"
        );
    }

    function _stepController(Plan memory plan, address verifier, address proxy, bool live)
        internal
        returns (address controller)
    {
        bool deployed;
        (controller, deployed) = _preflight(plan, 3, "WebAuthnController");
        if (!deployed) {
            _simulateTheLiveChainsPrecompile(live);
            vm.startBroadcast();
            address actual = vm.deployCode(CONTROLLER_ARTIFACT, abi.encode(verifier, proxy));
            vm.stopBroadcast();
            _requireLanded(actual, controller, "WebAuthnController");
        }
        require(
            IControllerProbe(controller).p256Fallback() == verifier,
            "identity REFUSED: the controller's p256Fallback() is not the planned verifier"
        );
        require(
            IControllerProbe(controller).signerImplementation() == proxy,
            "identity REFUSED: the controller's signerImplementation() is not the planned proxy"
        );
        _requireControllerMatchesTheChain(controller, live);
    }

    function _stepFactory(Plan memory plan) internal returns (address factory) {
        bool deployed;
        (factory, deployed) = _preflight(plan, 4, "RealWorldAssetsV3Factory");
        if (!deployed) {
            vm.startBroadcast();
            address actual = vm.deployCode(FACTORY_ARTIFACT);
            vm.stopBroadcast();
            _requireLanded(actual, factory, "RealWorldAssetsV3Factory");
        }
        require(
            keccak256(factory.code) == keccak256(vm.getDeployedCode(FACTORY_ARTIFACT)),
            "identity REFUSED: the code at the factory address is not this build's RealWorldAssetsV3Factory"
        );
        require(factory.code.length <= EIP170_LIMIT, "RealWorldAssetsV3Factory runtime exceeds EIP-170");
        console.log("  factory runtime bytecode size:", factory.code.length);
        _rehearseCollection(factory);
    }

    function _rehearseCollection(address factory) internal {
        address owner = 0x000000000000000000000000000000000000dEaD;
        bytes32 salt = keccak256("DeployPasskeyAndV3Stack.rehearsal");
        IRealWorldAssetsV3FactoryRehearsal f = IRealWorldAssetsV3FactoryRehearsal(factory);
        address predicted = f.computeAddress(salt, "Rehearsal", "RWA", owner);
        address created = f.createRealWorldAssetsV3Deterministic("Rehearsal", "RWA", owner, salt);
        require(created == predicted, "rehearsal REFUSED: computeAddress disagreed with the deploy");
        require(IOwnedCollection(created).owner() == owner, "rehearsal REFUSED: collection owner is wrong");
        console.log("  factory rehearsal OK - predicted, created and owned as expected (simulation only)");
    }
}
