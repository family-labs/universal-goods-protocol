// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

library P256Signer {
    uint256 internal constant PP =
        0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant NN =
        0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 internal constant GX =
        0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 internal constant GY =
        0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    function sign(bytes32 digest, uint256 d) internal view returns (uint256 r, uint256 s) {
        uint256 z = uint256(digest) % NN;

        for (uint256 i = 0; i < 16; i++) {
            uint256 k = uint256(keccak256(abi.encode(digest, d, i))) % NN;
            if (k == 0) continue;
            uint256 x = _scalarMulGX(k);
            r = x % NN;
            if (r == 0) continue;
            uint256 kInv = _invMod(k, NN);
            s = mulmod(kInv, addmod(z, mulmod(r, d, NN), NN), NN);
            if (s == 0) continue;

            if (s > NN / 2) s = NN - s;
            return (r, s);
        }
        revert("P256Signer: no signature found");
    }

    function publicKey(uint256 d) internal view returns (uint256 x, uint256 y) {
        (uint256 jx, uint256 jy, uint256 jz) = _scalarMulG(d);
        return _toAffine(jx, jy, jz);
    }

    function _scalarMulGX(uint256 k) private view returns (uint256 x) {
        (uint256 jx, uint256 jy, uint256 jz) = _scalarMulG(k);
        (x,) = _toAffine(jx, jy, jz);
    }

    function _scalarMulG(uint256 k) private pure returns (uint256 x, uint256 y, uint256 z) {

        for (uint256 i = 0; i < 256; i++) {
            (x, y, z) = _double(x, y, z);
            if ((k >> (255 - i)) & 1 == 1) {
                (x, y, z) = _addAffine(x, y, z, GX, GY);
            }
        }
    }

    function _sub(uint256 lhs, uint256 rhs) private pure returns (uint256) {
        return addmod(lhs, PP - (rhs % PP), PP);
    }

    function _double(uint256 x, uint256 y, uint256 z)
        private
        pure
        returns (uint256, uint256, uint256)
    {
        if (z == 0 || y == 0) return (0, 0, 0);
        uint256 zz = mulmod(z, z, PP);

        uint256 m = mulmod(3, mulmod(_sub(x, zz), addmod(x, zz, PP), PP), PP);
        uint256 yy = mulmod(y, y, PP);
        uint256 s = mulmod(4, mulmod(x, yy, PP), PP);
        uint256 x3 = _sub(mulmod(m, m, PP), mulmod(2, s, PP));
        uint256 y3 = _sub(mulmod(m, _sub(s, x3), PP), mulmod(8, mulmod(yy, yy, PP), PP));
        uint256 z3 = mulmod(2, mulmod(y, z, PP), PP);
        return (x3, y3, z3);
    }

    function _addAffine(uint256 x, uint256 y, uint256 z, uint256 ax, uint256 ay)
        private
        pure
        returns (uint256, uint256, uint256)
    {
        if (z == 0) return (ax, ay, 1);
        uint256 zz = mulmod(z, z, PP);
        uint256 u2 = mulmod(ax, zz, PP);
        uint256 s2 = mulmod(ay, mulmod(zz, z, PP), PP);
        uint256 h = _sub(u2, x);
        uint256 rr = _sub(s2, y);
        if (h == 0) {
            if (rr == 0) return _double(x, y, z);
            return (0, 0, 0);
        }
        uint256 h2 = mulmod(h, h, PP);
        uint256 h3 = mulmod(h, h2, PP);
        uint256 uh2 = mulmod(x, h2, PP);
        uint256 x3 = _sub(_sub(mulmod(rr, rr, PP), h3), mulmod(2, uh2, PP));
        uint256 y3 = _sub(mulmod(rr, _sub(uh2, x3), PP), mulmod(y, h3, PP));
        uint256 z3 = mulmod(z, h, PP);
        return (x3, y3, z3);
    }

    function _toAffine(uint256 x, uint256 y, uint256 z)
        private
        view
        returns (uint256 ax, uint256 ay)
    {
        if (z == 0) return (0, 0);
        uint256 zInv = _invMod(z, PP);
        uint256 zInv2 = mulmod(zInv, zInv, PP);
        ax = mulmod(x, zInv2, PP);
        ay = mulmod(y, mulmod(zInv2, zInv, PP), PP);
    }

    function _invMod(uint256 v, uint256 m) private view returns (uint256) {
        (bool ok, bytes memory res) = address(0x05).staticcall(
            abi.encode(uint256(32), uint256(32), uint256(32), v, m - 2, m)
        );
        require(ok, "P256Signer: modexp failed");
        return abi.decode(res, (uint256));
    }
}
