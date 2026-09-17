// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {EligibilityRegistry} from "../src/EligibilityRegistry.sol";

// specs/phase-3/verification-infrastructure.md §7.1
contract EligibilityRegistryTest is Test {
    EligibilityRegistry internal registry;
    address internal issuer = address(0xE55);
    address internal stranger = address(0xBAD);

    function setUp() public {
        vm.prank(issuer);
        registry = new EligibilityRegistry(issuer);
    }

    // Case 1
    function test_NonIssuerCannotPublishValidSetRoot() public {
        vm.prank(stranger);
        vm.expectRevert("not issuer");
        registry.publishValidSetRoot(bytes32(uint256(1)));
    }

    // Case 2
    function test_NonIssuerCannotPublishSanctionsRoot() public {
        vm.prank(stranger);
        vm.expectRevert("not issuer");
        registry.publishSanctionsRoot(bytes32(uint256(1)));
    }

    // Case 3
    function test_IssuerPublishesValidSetRoot() public {
        bytes32 root = bytes32(uint256(42));
        vm.prank(issuer);
        registry.publishValidSetRoot(root);

        assertEq(registry.currentEpoch(), 1);
        assertEq(registry.validSetRootAt(1), root);
    }

    // Case 4
    function test_TwoValidSetRootsRetrievableAtTheirRespectiveEpochs() public {
        bytes32 root1 = bytes32(uint256(1));
        bytes32 root2 = bytes32(uint256(2));

        vm.startPrank(issuer);
        registry.publishValidSetRoot(root1);
        registry.publishValidSetRoot(root2);
        vm.stopPrank();

        assertEq(registry.currentEpoch(), 2);
        assertEq(registry.validSetRootAt(1), root1);
        assertEq(registry.validSetRootAt(2), root2);
    }

    // Case 5
    function test_IssuerPublishesSanctionsRoot() public {
        bytes32 root = bytes32(uint256(7));
        vm.prank(issuer);
        registry.publishSanctionsRoot(root);

        assertEq(registry.sanctionsRoot(), root);
        assertEq(registry.currentEpoch(), 0);
    }

    // Case 5b
    function test_NonIssuerCannotApproveJurisdictionRoot() public {
        vm.prank(stranger);
        vm.expectRevert("not issuer");
        registry.approveJurisdictionRoot(bytes32(uint256(9)));
    }

    // Case 5c
    function test_IssuerApprovesJurisdictionRoot() public {
        bytes32 approved = bytes32(uint256(9));
        bytes32 neverApproved = bytes32(uint256(10));

        vm.prank(issuer);
        registry.approveJurisdictionRoot(approved);

        assertTrue(registry.approvedJurisdictionRoots(approved));
        assertFalse(registry.approvedJurisdictionRoots(neverApproved));
    }
}
