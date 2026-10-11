// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";

import {RealWorldAssetsV3} from "../src/RealWorldAssetsV3.sol";
import {UniversalProfileTestHelpers} from "./lib/UniversalProfileTestHelper.sol";

import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {LSP8Mintable} from "@lukso/lsp8-contracts/contracts/presets/LSP8Mintable.sol";
import {LSP25_VERSION} from "@lukso/lsp25-contracts/contracts/LSP25Constants.sol";

contract RealWorldAssetsV3HandoverGasTest is UniversalProfileTestHelpers {
    RealWorldAssetsV3 internal collection;

    UniversalProfile internal senderUP;
    UniversalProfile internal receiverUP;
    LSP6KeyManager internal senderKM;
    LSP6KeyManager internal receiverKM;

    uint256 internal constant SENDER_PK = 0xA11CE;
    uint256 internal constant RECEIVER_PK = 0xB0B;
    address internal senderController;
    address internal receiverController;

    address internal relayer = address(0x8E1A9E5);

    uint128 internal constant CHANNEL_ID = 0;

    uint256 internal constant UPI_BYTE_LENGTH = 12;

    function setUp() public override {
        super.setUp();

        senderController = vm.addr(SENDER_PK);
        receiverController = vm.addr(RECEIVER_PK);

        senderUP = _setUpUniversalProfileLikeBrowserExtension(senderController);
        receiverUP = _setUpUniversalProfileLikeBrowserExtension(receiverController);
        senderKM = LSP6KeyManager(payable(senderUP.owner()));
        receiverKM = LSP6KeyManager(payable(receiverUP.owner()));

        collection = new RealWorldAssetsV3("Acme Widget", "RWA", address(senderUP));

        _warmNonceChannel(senderKM, SENDER_PK);
        _warmNonceChannel(receiverKM, RECEIVER_PK);
    }

    function _upi(uint256 index) internal pure returns (bytes memory) {
        bytes memory out = new bytes(UPI_BYTE_LENGTH);
        for (uint256 i = 0; i < UPI_BYTE_LENGTH; i++) {
            out[i] = bytes1(uint8(48 + ((index + i * 7) % 10)));
        }

        out[0] = bytes1(uint8(65 + (index % 26)));
        out[1] = bytes1(uint8(65 + ((index / 26) % 26)));
        out[2] = bytes1(uint8(65 + ((index / 676) % 26)));
        return out;
    }

    function _tokenId(uint256 index) internal pure returns (bytes32) {
        return keccak256(_upi(index));
    }

    function _warmNonceChannel(LSP6KeyManager km, uint256 pk) internal {
        UniversalProfile up = UniversalProfile(payable(km.target()));
        bytes memory payload =
            abi.encodeWithSignature("setData(bytes32,bytes)", bytes32(uint256(0xDEAD)), hex"01");
        _relay(km, pk, up, payload);
    }

    function _relay(LSP6KeyManager km, uint256 pk, UniversalProfile, bytes memory payload)
        internal
        returns (uint256 executionGas, uint256 calldataGas)
    {
        uint256 nonce = km.getNonce(vm.addr(pk), CHANNEL_ID);
        bytes memory signature = _signRelayCall(address(km), pk, nonce, payload);

        bytes memory outer = abi.encodeWithSignature(
            "executeRelayCall(bytes,uint256,uint256,bytes)", signature, nonce, uint256(0), payload
        );
        calldataGas = _calldataGas(outer);

        vm.prank(relayer);
        uint256 before = gasleft();
        km.executeRelayCall(signature, nonce, 0, payload);
        executionGas = before - gasleft();
    }

    function _signRelayCall(address keyManager, uint256 pk, uint256 nonce, bytes memory payload)
        internal
        view
        returns (bytes memory)
    {
        bytes memory encoded = abi.encodePacked(
            LSP25_VERSION, block.chainid, nonce, uint256(0), uint256(0), payload
        );
        bytes32 digest = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x00), keyManager, encoded));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _calldataGas(bytes memory data) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < data.length; i++) {
            total += data[i] == 0 ? 4 : 16;
        }
    }

    function _mint(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            bytes memory payload = abi.encodeWithSignature(
                "execute(uint256,address,uint256,bytes)",
                uint256(0),
                address(collection),
                uint256(0),
                abi.encodeWithSelector(
                    LSP8Mintable.mint.selector, address(senderUP), _tokenId(i), true, bytes("")
                )
            );
            _relay(senderKM, SENDER_PK, senderUP, payload);
        }
    }

    function _offerBatchPayload(uint256 count) internal view returns (bytes memory) {
        uint256[] memory operations = new uint256[](count);
        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory datas = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            operations[i] = 0;
            targets[i] = address(collection);
            values[i] = 0;
            datas[i] = abi.encodeWithSignature(
                "authorizeOperator(address,bytes32,bytes)",
                address(receiverUP),
                _tokenId(i),
                _upi(i)
            );
        }

        return abi.encodeWithSignature(
            "executeBatch(uint256[],address[],uint256[],bytes[])", operations, targets, values, datas
        );
    }

    function _revokeBatchPayload(uint256 count) internal view returns (bytes memory) {
        uint256[] memory operations = new uint256[](count);
        address[] memory targets = new address[](count);
        uint256[] memory values = new uint256[](count);
        bytes[] memory datas = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            operations[i] = 0;
            targets[i] = address(collection);
            values[i] = 0;
            datas[i] = abi.encodeWithSignature(
                "revokeOperator(address,bytes32,bool,bytes)",
                address(receiverUP),
                _tokenId(i),
                true,
                bytes("")
            );
        }

        return abi.encodeWithSignature(
            "executeBatch(uint256[],address[],uint256[],bytes[])", operations, targets, values, datas
        );
    }

    function _acceptBatchPayload(uint256 count) internal view returns (bytes memory) {
        address[] memory from = new address[](count);
        address[] memory to = new address[](count);
        bytes32[] memory ids = new bytes32[](count);
        bool[] memory force = new bool[](count);
        bytes[] memory datas = new bytes[](count);

        for (uint256 i = 0; i < count; i++) {
            from[i] = address(senderUP);
            to[i] = address(receiverUP);
            ids[i] = _tokenId(i);
            force[i] = true;
            datas[i] = _upi(i);
        }

        return abi.encodeWithSignature(
            "execute(uint256,address,uint256,bytes)",
            uint256(0),
            address(collection),
            uint256(0),
            abi.encodeWithSignature(
                "transferBatch(address[],address[],bytes32[],bool[],bytes[])",
                from,
                to,
                ids,
                force,
                datas
            )
        );
    }

    function _report(string memory label, uint256 count, uint256 execGas, uint256 cdGas)
        internal
        pure
    {
        uint256 total = execGas + 21_000 + cdGas;
        console2.log(
            string.concat(
                "  ",
                label,
                "  n=",
                vm.toString(count),
                "  exec=",
                vm.toString(execGas),
                "  calldata=",
                vm.toString(cdGas),
                "  TOTAL=",
                vm.toString(total),
                "  per-item=",
                vm.toString(total / count)
            )
        );
    }

    function _measure(uint256 count) internal {
        _mint(count);

        (uint256 offerExec, uint256 offerCd) =
            _relay(senderKM, SENDER_PK, senderUP, _offerBatchPayload(count));
        _report("OFFER  (sender, executeBatch of authorizeOperator)", count, offerExec, offerCd);

        (uint256 acceptExec, uint256 acceptCd) =
            _relay(receiverKM, RECEIVER_PK, receiverUP, _acceptBatchPayload(count));
        _report("ACCEPT (receiver, one transferBatch)             ", count, acceptExec, acceptCd);

        for (uint256 i = 0; i < count; i++) {
            assertEq(collection.tokenOwnerOf(_tokenId(i)), address(receiverUP));
        }
    }

    function test_Gas_01_OnePassport() public {
        console2.log("=== V3 HAND-OVER, MEASURED (1 passport) ===");
        _measure(1);
    }

    function test_Gas_02_TenPassports() public {
        console2.log("=== V3 HAND-OVER, MEASURED (10 passports) ===");
        _measure(10);
    }

    function test_Gas_03_OneHundredPassports() public {
        console2.log("=== V3 HAND-OVER, MEASURED (100 passports) ===");
        _measure(100);
    }

    function test_Gas_04_WithdrawRevokesOnChain() public {
        console2.log("=== V3 WITHDRAWAL (revokeOperator), MEASURED ===");

        uint256[3] memory counts = [uint256(1), 10, 100];
        for (uint256 c = 0; c < counts.length; c++) {
            uint256 count = counts[c];
            setUp();
            _mint(count);
            _relay(senderKM, SENDER_PK, senderUP, _offerBatchPayload(count));

            (uint256 exec, uint256 cd) =
                _relay(senderKM, SENDER_PK, senderUP, _revokeBatchPayload(count));
            _report("WITHDRAW (sender, executeBatch of revokeOperator)", count, exec, cd);

            vm.expectRevert();
            this.pullAsReceiver(count);
        }
    }

    function pullAsReceiver(uint256 count) external {
        _relay(receiverKM, RECEIVER_PK, receiverUP, _acceptBatchPayload(count));
    }

    function test_Gas_05_TheCeilingIsGasNotAnArrayLength() public {
        console2.log("=== WHERE ONE SIGNATURE STOPS COVERING MORE PASSPORTS ===");
        console2.log("  LUKSO block gas limit = 42,000,000");

        uint256[3] memory counts = [uint256(200), 300, 400];
        for (uint256 c = 0; c < counts.length; c++) {
            uint256 count = counts[c];
            setUp();
            _mint(count);

            (uint256 offerExec, uint256 offerCd) =
                _relay(senderKM, SENDER_PK, senderUP, _offerBatchPayload(count));
            _report("OFFER  (sender, executeBatch of authorizeOperator)", count, offerExec, offerCd);

            (uint256 acceptExec, uint256 acceptCd) =
                _relay(receiverKM, RECEIVER_PK, receiverUP, _acceptBatchPayload(count));
            _report("ACCEPT (receiver, one transferBatch)             ", count, acceptExec, acceptCd);

            for (uint256 i = 0; i < count; i++) {
                assertEq(collection.tokenOwnerOf(_tokenId(i)), address(receiverUP));
            }
        }
    }

    function test_TheUpiLengthUsedForTheseMeasurementsIsTwelveBytes() public pure {
        assertEq(_upi(0).length, 12);
        assertEq(_upi(999).length, 12);
    }

    function test_TheGeneratedIdentifiersAreDistinct() public pure {
        assertTrue(_tokenId(0) != _tokenId(1));
        assertTrue(_tokenId(1) != _tokenId(99));
        assertTrue(_tokenId(26) != _tokenId(0));
    }
}
