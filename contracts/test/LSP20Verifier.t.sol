// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {LSP20Verifier} from "../src/LSP20Verifier.sol";
import {DemoLSP8Token} from "../src/DemoLSP8Token.sol";

contract LSP20VerifierTest is Test {
    uint256 signerPk = 0x12345;
    address signer;
    LSP20Verifier verifier;
    DemoLSP8Token token;

    function setUp() public {
        signer = vm.addr(signerPk);
        verifier = new LSP20Verifier(signer);
        token = new DemoLSP8Token("Demo", "D", address(this), address(0xdead));
    }

    function _sig(bytes32 digest, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _wrap(bytes memory data, bytes memory sig) internal pure returns (bytes memory) {
        return abi.encode(data, sig);
    }

    function _call(bytes memory callData) internal returns (bytes4) {

        return verifier.lsp20VerifyCall(address(this), address(token), address(this), 0, callData);
    }

    function testRevertsOnZeroTarget() public {
        vm.expectRevert(bytes("LSP20: target zero-address"));
        verifier.lsp20VerifyCall(address(this), address(0), address(this), 0, bytes(""));
    }

    function testRevertsOnShortCalldata() public {
        vm.expectRevert(bytes("LSP20: invalid calldata"));
        _call(hex"00");
    }

    function testRevertsOnUnsupportedSelector() public {

        bytes memory cd = bytes.concat(bytes4(0xFFFFFFFF), bytes("abcd"));
        vm.expectRevert(bytes("LSP20: selector not supported"));
        _call(cd);
    }

    function testMintPathValidAndInvalidSignature() public {
        address to = address(0xA1);
        bytes32 tokenId = keccak256("T1");
        bool force_ = true;
        bytes memory data = bytes("hello");

        bytes32 dataHash = keccak256(data);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Mint(address target,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
                ),
                address(token),
                to,
                tokenId,
                dataHash,
                keccak256(bytes("MINT"))
            )
        );
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("LSP20")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        bytes memory goodSig = _sig(digest, signerPk);
        bytes memory badSig = _sig(digest, signerPk + 1);
        bytes memory goodEnvelope = _wrap(data, goodSig);
        bytes memory badEnvelope = _wrap(data, badSig);

        vm.expectRevert(bytes("LSP20: invalid signature (mint)"));
        _call(
            abi.encodePacked(
                DemoLSP8Token.mintWithVerification.selector,
                abi.encode(to, tokenId, force_, badEnvelope)
            )
        );

        bytes4 ret = _call(
            abi.encodePacked(
                DemoLSP8Token.mintWithVerification.selector,
                abi.encode(to, tokenId, force_, goodEnvelope)
            )
        );
        assertEq(ret & 0xFFFFFF00, bytes4(bytes3(verifier.lsp20VerifyCall.selector)));

        assertEq(uint8(ret[3]), 0);
    }

    function testTransferAuthorizeSetDataPaths() public {
        address from = address(0xB1);
        address to = address(0xB2);
        bytes32 tokenId = keccak256("T2");
        bytes memory data = bytes("d");
        bytes32 dataHash = keccak256(data);

        bytes32 structHashTransfer = keccak256(
            abi.encode(
                keccak256(
                    "Transfer(address target,address from,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
                ),
                address(token),
                from,
                to,
                tokenId,
                dataHash,
                keccak256(bytes("TRANSFER"))
            )
        );

        address operator = address(0xCC);
        bytes32 structHashAuth = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address target,address operator,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
                ),
                address(token),
                operator,
                tokenId,
                dataHash,
                keccak256(bytes("AUTHORIZE_OPERATOR"))
            )
        );

        bytes32 dataKey = keccak256("key");
        bytes32 structHashSetData = keccak256(
            abi.encode(
                keccak256("SetData(address target,bytes32 dataKey,bytes32 dataHash,bytes32 tag)"),
                address(token),
                dataKey,
                dataHash,
                keccak256(bytes("SET_DATA"))
            )
        );

        bytes32 structHashSetDataForToken = keccak256(
            abi.encode(
                keccak256(
                    "SetDataForToken(address target,bytes32 tokenId,bytes32 dataKey,bytes32 dataHash,bytes32 tag)"
                ),
                address(token),
                tokenId,
                dataKey,
                dataHash,
                keccak256(bytes("SET_DATA_FOR_TOKEN"))
            )
        );

        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("LSP20")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );

        _checkPath(
            DemoLSP8Token.transfer.selector,
            abi.encode(
                from,
                to,
                tokenId,
                true,
                _wrap(data, _sig(_digest(domain, structHashTransfer), signerPk))
            )
        );
        _checkPath(
            DemoLSP8Token.authorizeOperator.selector,
            abi.encode(
                operator, tokenId, _wrap(data, _sig(_digest(domain, structHashAuth), signerPk))
            )
        );
        _checkPath(
            DemoLSP8Token.setData.selector,
            abi.encode(dataKey, _wrap(data, _sig(_digest(domain, structHashSetData), signerPk)))
        );
        _checkPath(
            DemoLSP8Token.setDataForTokenId.selector,
            abi.encode(
                tokenId,
                dataKey,
                _wrap(data, _sig(_digest(domain, structHashSetDataForToken), signerPk))
            )
        );
    }

    function _digest(bytes32 domain, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    function _checkPath(bytes4 sel, bytes memory encodedPayload) internal {
        bytes4 ret = _call(abi.encodePacked(sel, encodedPayload));
        assertEq(uint8(ret[3]), 0);
    }

    function testVerifyCallResultSelector() public {
        bytes4 out = verifier.lsp20VerifyCallResult(0x0, bytes(""));
        assertEq(out, verifier.lsp20VerifyCallResult.selector);
    }
}
