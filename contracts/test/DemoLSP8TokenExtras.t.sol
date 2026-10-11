// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {DemoLSP8Token} from "../src/DemoLSP8Token.sol";

contract DemoLSP8TokenExtrasTest is Test {
    DemoLSP8Token token;

    function setUp() public {
        token = new DemoLSP8Token("Demo", "D", address(this), address(0x1));
    }

    function testUpdateVerifier() public {
        token.updateVerifier(address(0xBEEF));

    }
}
