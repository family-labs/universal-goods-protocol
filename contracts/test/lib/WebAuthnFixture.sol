// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {WebAuthn} from "../../src/WebAuthn.sol";
import {P256Signer} from "./P256Signer.sol";

library WebAuthnFixture {

    bytes1 internal constant FLAGS_UP_UV = 0x05;

    bytes1 internal constant FLAGS_UP_ONLY = 0x01;

    bytes1 internal constant FLAGS_NONE = 0x00;

    uint256 internal constant TYPE_INDEX = 1;
    uint256 internal constant CHALLENGE_INDEX = 23;

    function rpIdHash() internal pure returns (bytes32) {
        return sha256(bytes("universalgoods.xyz"));
    }

    function make(bytes32 challenge, uint256 privateKey)
        internal
        view
        returns (WebAuthn.Assertion memory)
    {
        return makeWith(challenge, privateKey, rpIdHash(), FLAGS_UP_UV, "webauthn.get");
    }

    function makeWith(
        bytes32 challenge,
        uint256 privateKey,
        bytes32 rpId,
        bytes1 flags,
        string memory ceremonyType
    ) internal view returns (WebAuthn.Assertion memory assertion) {
        bytes memory authenticatorData = abi.encodePacked(rpId, flags, uint32(1));
        bytes memory clientDataJSON = abi.encodePacked(
            '{"type":"',
            ceremonyType,
            '","challenge":"',
            base64UrlEncode32(challenge),
            '","origin":"https://universalgoods.xyz","crossOrigin":false}'
        );

        bytes32 signedHash =
            sha256(abi.encodePacked(authenticatorData, sha256(clientDataJSON)));
        (uint256 r, uint256 s) = P256Signer.sign(signedHash, privateKey);

        assertion = WebAuthn.Assertion({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,

            typeIndex: TYPE_INDEX,
            challengeIndex: 11 + bytes(ceremonyType).length,
            r: r,
            s: s
        });
    }

    function base64UrlEncode32(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        uint256 v = uint256(data);
        bytes memory out = new bytes(43);

        for (uint256 i = 0; i < 42; i++) {
            out[i] = alphabet[(v >> (256 - 6 * (i + 1))) & 0x3F];
        }
        out[42] = alphabet[(v & 0x0F) << 2];

        return string(out);
    }
}
