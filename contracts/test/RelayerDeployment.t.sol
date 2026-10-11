// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { LSP23LinkedContractsFactory } from "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/LSP23LinkedContractsFactory.sol";
import { ILSP23LinkedContractsFactory } from "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/ILSP23LinkedContractsFactory.sol";
import { UniversalProfileInit } from "@lukso/lsp-smart-contracts/contracts/UniversalProfileInit.sol";
import { LSP6KeyManagerInit } from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManagerInit.sol";
import { LSP1UniversalReceiverDelegateUP } from "@lukso/lsp-smart-contracts/contracts/LSP1UniversalReceiver/LSP1UniversalReceiverDelegateUP/LSP1UniversalReceiverDelegateUP.sol";
import { UniversalProfileInitPostDeploymentModule } from "@lukso/lsp-smart-contracts/contracts/LSP23LinkedContractsFactory/modules/UniversalProfileInitPostDeploymentModule.sol";
import { UniversalProfile } from "@lukso/lsp-smart-contracts/contracts/UniversalProfile.sol";
import { LSP6KeyManager } from "@lukso/lsp-smart-contracts/contracts/LSP6KeyManager/LSP6KeyManager.sol";
import { _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY } from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import { LSP8IdentifiableDigitalAsset } from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import { _LSP4_TOKEN_TYPE_NFT } from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import { _LSP8_TOKENID_FORMAT_HASH } from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";
import { _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, _PERMISSION_SUPER_SETDATA } from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import { _LSP5_RECEIVED_ASSETS_ARRAY_KEY, _LSP5_RECEIVED_ASSETS_MAP_KEY_PREFIX } from "@lukso/lsp5-contracts/contracts/LSP5Constants.sol";
import { IERC725Y } from "@erc725/smart-contracts/contracts/interfaces/IERC725Y.sol";

import { MockLSP8 } from "./MockLSP8.sol";

contract RelayerDeploymentTest is Test {
    LSP23LinkedContractsFactory factory;
    UniversalProfileInit upInit;
    LSP6KeyManagerInit kmInit;
    LSP1UniversalReceiverDelegateUP urd;
    UniversalProfileInitPostDeploymentModule postDeploymentModule;

    function setUp() public {
        factory = new LSP23LinkedContractsFactory();
        upInit = new UniversalProfileInit();
        kmInit = new LSP6KeyManagerInit();
        urd = new LSP1UniversalReceiverDelegateUP();
        postDeploymentModule = new UniversalProfileInitPostDeploymentModule();
    }

    function testDeployUP() public {
        bytes32 salt = keccak256("test-salt");

        bytes memory upInitCalldata = abi.encodeWithSelector(
            UniversalProfileInit.initialize.selector,
            address(postDeploymentModule)
        );

        ILSP23LinkedContractsFactory.PrimaryContractDeploymentInit memory primaryInit = ILSP23LinkedContractsFactory.PrimaryContractDeploymentInit({
            salt: salt,
            fundingAmount: 0,
            implementationContract: address(upInit),
            initializationCalldata: upInitCalldata
        });

        ILSP23LinkedContractsFactory.SecondaryContractDeploymentInit memory secondaryInit = ILSP23LinkedContractsFactory.SecondaryContractDeploymentInit({
            fundingAmount: 0,
            implementationContract: address(kmInit),
            addPrimaryContractAddress: true,
            initializationCalldata: abi.encodeWithSelector(LSP6KeyManagerInit.initialize.selector),
            extraInitializationParams: ""
        });

        address controller = vm.addr(1);

        bytes32 permissionsKey = bytes32(abi.encodePacked(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
            bytes2(0),
            controller
        ));

        bytes32 urdPermissionsKey = bytes32(abi.encodePacked(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
            bytes2(0),
            address(urd)
        ));

        bytes32[] memory dataKeys = new bytes32[](3);
        dataKeys[0] = _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY;
        dataKeys[1] = permissionsKey;
        dataKeys[2] = urdPermissionsKey;

        bytes[] memory dataValues = new bytes[](3);
        dataValues[0] = abi.encodePacked(address(urd));
        dataValues[1] = abi.encodePacked(_PERMISSION_SUPER_SETDATA);
        dataValues[2] = abi.encodePacked(_PERMISSION_SUPER_SETDATA);

        bytes memory postDeploymentCalldata = abi.encode(
            dataKeys,
            dataValues
        );

        (address up, address km) = factory.deployERC1167Proxies(
            primaryInit,
            secondaryInit,
            address(postDeploymentModule),
            postDeploymentCalldata
        );

        assertTrue(up != address(0), "UP address should not be 0");
        assertTrue(km != address(0), "KM address should not be 0");

        UniversalProfile upContract = UniversalProfile(payable(up));
        LSP6KeyManager kmContract = LSP6KeyManager(km);

        assertEq(upContract.owner(), km, "UP owner should be KM");

        assertEq(kmContract.target(), up, "KM target should be UP");

        bytes memory storedUrd = upContract.getData(_LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY);
        assertEq(storedUrd, abi.encodePacked(address(urd)), "URD should be set in UP");

        bytes memory storedPermissions = upContract.getData(permissionsKey);
        assertEq(storedPermissions, abi.encodePacked(_PERMISSION_SUPER_SETDATA), "Controller should have SETDATA permissions");

        bytes32 testKey = keccak256("TEST_KEY");
        bytes memory testValue = hex"1234";
        bytes memory setDataPayload = abi.encodeWithSelector(IERC725Y.setData.selector, testKey, testValue);

        vm.prank(controller);
        kmContract.execute(setDataPayload);

        assertEq(upContract.getData(testKey), testValue, "Data should be set via KeyManager");

        MockLSP8 token = new MockLSP8(address(this));
        bytes32 tokenId = keccak256("token1");

        token.mint(up, tokenId);

        bytes memory receivedAssetsCount = upContract.getData(_LSP5_RECEIVED_ASSETS_ARRAY_KEY);
        assertGt(receivedAssetsCount.length, 0, "Received assets count should be set");

        bytes32 mapKey = bytes32(abi.encodePacked(
            _LSP5_RECEIVED_ASSETS_MAP_KEY_PREFIX,
            bytes2(0),
            address(token)
        ));
        bytes memory mapValue = upContract.getData(mapKey);
        assertGt(mapValue.length, 0, "Asset should be in the map");
    }
}
