// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {LSP16UniversalFactory} from "@lukso/lsp-smart-contracts/contracts/LSP16UniversalFactory/LSP16UniversalFactory.sol";
import {LSP11SocialRecovery} from "@lukso/lsp11-contracts/contracts/LSP11SocialRecovery.sol";
import {_INTERFACEID_LSP11} from "@lukso/lsp11-contracts/contracts/LSP11Constants.sol";
import {UniversalFactoryDeployer} from "./DeployUniversalFactory.s.sol";

contract DeployLSP11SocialRecovery is UniversalFactoryDeployer {
    bytes32 public constant LSP11_SALT = keccak256("UG_LSP11_SOCIAL_RECOVERY_0_1_7");
    uint256 internal constant LUKSO_MAINNET = 42;
    uint256 internal constant LUKSO_TESTNET = 4201;

    function run() external returns (address lsp11) {
        if (block.chainid == LUKSO_MAINNET || block.chainid == LUKSO_TESTNET) {
            require(
                vm.envOr("LSP11_DEPLOY_DECIDED", uint256(0)) == 1,
                "Deploying LSP11 to a public chain needs an explicit opt-in. Set LSP11_DEPLOY_DECIDED=1 once the deployment has been reviewed."
            );
        }

        if (vm.envExists("PRIVATE_KEY")) vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        else vm.startBroadcast();

        LSP16UniversalFactory factory = LSP16UniversalFactory(deployUniversalFactory());
        bytes memory creationCode = type(LSP11SocialRecovery).creationCode;
        address expected = factory.computeAddress(keccak256(creationCode), LSP11_SALT, false, "");

        if (expected.code.length > 0) {
            console.log("LSP11SocialRecovery already deployed at:", expected);
            lsp11 = expected;
        } else {
            lsp11 = factory.deployCreate2(creationCode, LSP11_SALT);
            require(lsp11 == expected, "LSP11 address mismatch");
            console.log("LSP11SocialRecovery deployed at:", lsp11);
        }
        vm.stopBroadcast();

        require(LSP11SocialRecovery(lsp11).supportsInterface(_INTERFACEID_LSP11), "not LSP11");
    }
}
