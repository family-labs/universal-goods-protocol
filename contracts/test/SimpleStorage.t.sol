// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/SimpleStorage.sol";

contract SimpleStorageTest is Test {
    SimpleStorage store;
    address alice = address(0x1);

    function setUp() public {
        store = new SimpleStorage();
    }

    function testSetAndGet() public {
        bytes32 key = keccak256("my-key");
        string memory value = "hello world";

        vm.prank(alice);
        store.set(key, value);

        string memory got = store.get(key);
        assertEq(got, value);
    }

    function testOverwriteValue() public {
        bytes32 key = keccak256("my-key");
        vm.prank(alice);
        store.set(key, "first");
        vm.prank(alice);
        store.set(key, "second");

        string memory got = store.get(key);
        assertEq(got, "second");
    }

    function testDefaultEmpty() public {
        bytes32 key = keccak256("unknown-key");
        string memory got = store.get(key);
        assertEq(got, "");
    }
}
