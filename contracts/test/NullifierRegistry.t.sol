// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {NullifierRegistry} from "../src/NullifierRegistry.sol";

// specs/phase-3/verification-infrastructure.md §7.2. Deployed standalone
// (not through OfferingPolicy) - this test contract stands in as the
// "authorized" caller, exactly as §3.2 describes for the real deployment.
contract NullifierRegistryTest is Test {
    NullifierRegistry internal nullifiers;
    address internal stranger = address(0xBAD);

    function setUp() public {
        nullifiers = new NullifierRegistry();
        nullifiers.setAuthorized(address(this));
    }

    // Case 6
    function test_FreshNullifierConsumedByAuthorizedAddress() public {
        nullifiers.consumeIfUnused(1);
        assertTrue(nullifiers.consumed(1));
    }

    // Case 7
    function test_SameNullifierTwiceReverts() public {
        nullifiers.consumeIfUnused(1);
        vm.expectRevert("nullifier already used");
        nullifiers.consumeIfUnused(1);
    }

    // Case 8
    function test_TwoDistinctNullifiersBothSucceed() public {
        nullifiers.consumeIfUnused(1);
        nullifiers.consumeIfUnused(2);
        assertTrue(nullifiers.consumed(1));
        assertTrue(nullifiers.consumed(2));
    }

    // Case 8b
    function test_NonAuthorizedAddressCannotConsume() public {
        vm.prank(stranger);
        vm.expectRevert("not authorized");
        nullifiers.consumeIfUnused(1);
    }

    // Case 8c
    function test_SetAuthorizedCannotBeCalledTwice() public {
        vm.expectRevert("already set");
        nullifiers.setAuthorized(stranger);
    }

    // Case 8d
    function test_NonDeployerCannotCallSetAuthorizedFirst() public {
        NullifierRegistry fresh = new NullifierRegistry();
        vm.prank(stranger);
        vm.expectRevert("not deployer");
        fresh.setAuthorized(stranger);
    }
}
