// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Betcaster} from "../src/betcaster.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract BetcasterOwnableTest is Test {
    Betcaster public betcaster;

    // Test addresses
    address public owner = makeAddr("owner");
    address public newOwner = makeAddr("newOwner");
    address public unauthorizedUser = makeAddr("unauthorizedUser");
    address public randomUser = makeAddr("randomUser");

    // Test constants
    uint256 public constant PROTOCOL_FEE = 100;

    // Events from Ownable contract
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        // Deploy contract with owner as the deployer
        vm.prank(owner);
        betcaster = new Betcaster(PROTOCOL_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerIsSetCorrectlyInConstructor() public view {
        assertEq(betcaster.owner(), owner);
    }

    function testOwnerCanTransferOwnership() public {
        // Expect the OwnershipTransferred event
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, newOwner);

        vm.prank(owner);
        betcaster.transferOwnership(newOwner);

        // Verify ownership has been transferred
        assertEq(betcaster.owner(), newOwner);
    }

    function testNonOwnerCannotTransferOwnership() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        betcaster.transferOwnership(newOwner);

        // Verify ownership hasn't changed
        assertEq(betcaster.owner(), owner);
    }

    function testCannotTransferOwnershipToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        betcaster.transferOwnership(address(0));

        // Verify ownership hasn't changed
        assertEq(betcaster.owner(), owner);
    }

    function testOwnerCanRenounceOwnership() public {
        // Expect the OwnershipTransferred event to zero address
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, address(0));

        vm.prank(owner);
        betcaster.renounceOwnership();

        // Verify ownership has been renounced
        assertEq(betcaster.owner(), address(0));
    }

    function testNonOwnerCannotRenounceOwnership() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        betcaster.renounceOwnership();

        // Verify ownership hasn't changed
        assertEq(betcaster.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TRANSFER FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteOwnershipTransferFlow() public {
        // Initial state
        assertEq(betcaster.owner(), owner);

        // Transfer ownership
        vm.prank(owner);
        betcaster.transferOwnership(newOwner);
        assertEq(betcaster.owner(), newOwner);

        // New owner can transfer again
        address anotherOwner = makeAddr("anotherOwner");
        vm.prank(newOwner);
        betcaster.transferOwnership(anotherOwner);
        assertEq(betcaster.owner(), anotherOwner);

        // Original owner can no longer transfer
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        betcaster.transferOwnership(randomUser);
    }

    function testOwnershipTransferWithMultipleUsers() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // Only owner can transfer
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        betcaster.transferOwnership(user2);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        betcaster.transferOwnership(user3);

        // Owner can still transfer
        vm.prank(owner);
        betcaster.transferOwnership(user1);
        assertEq(betcaster.owner(), user1);
    }

    /*//////////////////////////////////////////////////////////////
                        RENOUNCE OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testRenounceOwnershipMakesContractOwnerless() public {
        vm.prank(owner);
        betcaster.renounceOwnership();

        assertEq(betcaster.owner(), address(0));

        // No one can transfer ownership after renouncing
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        betcaster.transferOwnership(newOwner);

        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        betcaster.transferOwnership(randomUser);
    }

    function testCannotRenounceOwnershipTwice() public {
        vm.prank(owner);
        betcaster.renounceOwnership();

        // Try to renounce again (should fail)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        betcaster.renounceOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransferOwnershipToSameOwner() public {
        // Should work but not change anything
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, owner);

        vm.prank(owner);
        betcaster.transferOwnership(owner);

        assertEq(betcaster.owner(), owner);
    }

    function testOwnershipAfterContractDeployment() public {
        // Deploy a new contract with different deployer
        address differentDeployer = makeAddr("differentDeployer");

        vm.prank(differentDeployer);
        Betcaster newBetcaster = new Betcaster(PROTOCOL_FEE);

        assertEq(newBetcaster.owner(), differentDeployer);
        assertNotEq(newBetcaster.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzOwnershipTransfer(address _newOwner) public {
        // Skip zero address as it should revert
        vm.assume(_newOwner != address(0));

        vm.prank(owner);
        betcaster.transferOwnership(_newOwner);

        assertEq(betcaster.owner(), _newOwner);
    }

    function testFuzzUnauthorizedOwnershipTransfer(address _unauthorizedUser, address _targetOwner) public {
        // Ensure the unauthorized user is not the current owner
        vm.assume(_unauthorizedUser != owner);
        vm.assume(_targetOwner != address(0));

        vm.prank(_unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _unauthorizedUser));
        betcaster.transferOwnership(_targetOwner);

        // Verify ownership hasn't changed
        assertEq(betcaster.owner(), owner);
    }

    function testFuzzUnauthorizedRenounceOwnership(address _unauthorizedUser) public {
        // Ensure the unauthorized user is not the current owner
        vm.assume(_unauthorizedUser != owner);

        vm.prank(_unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _unauthorizedUser));
        betcaster.renounceOwnership();

        // Verify ownership hasn't changed
        assertEq(betcaster.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnershipIntegrationWithBetcasterFunctions() public {
        // This test ensures that ownership doesn't interfere with normal contract functions
        // Since Betcaster doesn't have owner-only functions yet, we test that ownership
        // coexists with regular functionality

        // Verify owner is set
        assertEq(betcaster.owner(), owner);

        // Verify protocol fee is accessible (public variable)
        assertEq(betcaster.s_prtocolFee(), PROTOCOL_FEE);

        // Verify bet number starts at 0
        assertEq(betcaster.getCurrentBetNumber(), 0);

        // Transfer ownership and verify contract still functions
        vm.prank(owner);
        betcaster.transferOwnership(newOwner);

        assertEq(betcaster.owner(), newOwner);
        assertEq(betcaster.s_prtocolFee(), PROTOCOL_FEE);
        assertEq(betcaster.getCurrentBetNumber(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnershipSecurityScenarios() public {
        // Scenario 1: Multiple users trying to claim ownership
        address attacker1 = makeAddr("attacker1");
        address attacker2 = makeAddr("attacker2");

        vm.prank(attacker1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker1));
        betcaster.transferOwnership(attacker1);

        vm.prank(attacker2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker2));
        betcaster.transferOwnership(attacker2);

        // Verify owner is still the original
        assertEq(betcaster.owner(), owner);

        // Scenario 2: After ownership transfer, old owner cannot reclaim
        vm.prank(owner);
        betcaster.transferOwnership(newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        betcaster.transferOwnership(owner);

        assertEq(betcaster.owner(), newOwner);
    }
}
