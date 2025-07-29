// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {BetTypes} from "../src/BetTypes.sol";
import {DeployBetcaster} from "../script/DeployBetcaster.s.sol";
import {ArbiterManagementEngine} from "../src/arbiterManagementEngine.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract ArbiterManagementEngineTest is Test {
    Betcaster public betcaster;
    BetManagementEngine public betManagementEngine;
    ArbiterManagementEngine public arbiterManagementEngine;
    ERC20Mock public mockToken;

    // Test addresses
    address public maker = makeAddr("maker");
    address[] public taker = [makeAddr("taker")];
    address[] public arbiter = [makeAddr("arbiter")];
    address[] public user1 = [makeAddr("user1")];
    address[] public user2 = [makeAddr("user2")];
    address public owner;

    // Test constants
    uint256 public constant PROTOCOL_FEE = 100; // 1%
    uint256 public constant BET_AMOUNT = 1000e18;
    uint256 public constant ARBITER_FEE = 50; // 0.5%
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000000e18;
    bool public constant CAN_SETTLE_EARLY = false;
    string public constant BET_AGREEMENT = "Team A will win the match";

    // Events for testing
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet bet);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event ArbiterAcceptedRole(uint256 indexed betNumber, address indexed arbiter);
    event WinnerSelected(uint256 indexed betNumber, bool indexed resolvedTrue, BetTypes.Bet bet);
    event AllowListUpdated(address indexed address_, bool indexed allowed);
    event AllowListEnforcementUpdated(bool indexed isAllowListEnforced);

    function setUp() public {
        // Deploy contracts
        DeployBetcaster deployer = new DeployBetcaster();
        address wethTokenAddr;
        (betcaster, betManagementEngine, arbiterManagementEngine, wethTokenAddr) = deployer.run();
        mockToken = new ERC20Mock();

        owner = arbiterManagementEngine.owner();

        // Mint tokens to test addresses
        mockToken.mint(maker, INITIAL_TOKEN_SUPPLY);
        mockToken.mint(taker[0], INITIAL_TOKEN_SUPPLY);
        mockToken.mint(user1[0], INITIAL_TOKEN_SUPPLY);
        mockToken.mint(user2[0], INITIAL_TOKEN_SUPPLY);

        // Approve betcaster contract to spend tokens
        vm.prank(maker);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.prank(taker[0]);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.prank(user1[0]);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.prank(user2[0]);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.warp(block.timestamp + 1 days);

        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );
    }

    // Helper function to set up a bet ready for arbiter acceptance
    function _setupBetForArbiter() internal {
        vm.prank(taker[0]);
        betManagementEngine.acceptBet(1);
    }

    // Helper function to set up a bet in process (arbiter has accepted)
    function _setupBetInProcess() internal {
        _setupBetForArbiter();
        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(1);
    }

    /*//////////////////////////////////////////////////////////////
                        ARBITER ACCEPT ROLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testArbiterAcceptRole() public {
        vm.prank(taker[0]);
        betManagementEngine.acceptBet(1);

        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(1, arbiter[0]);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(1).arbiter[0], arbiter[0]);
    }

    function testArbiterAcceptRole_RevertWhen_BetNotWaitingForArbiter() public {
        // Bet is still WAITING_FOR_TAKER
        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__BetNotWaitingForArbiter.selector);
        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(1);
    }

    function testArbiterAcceptRole_RevertWhen_WrongArbiter() public {
        _setupBetForArbiter();

        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__NotArbiter.selector);
        vm.prank(user1[0]); // Wrong arbiter
        arbiterManagementEngine.ArbiterAcceptRole(1);
    }

    function testArbiterAcceptRole_WithZeroAddressArbiter() public {
        address[] memory emptyArbiter = new address[](1);
        emptyArbiter[0] = address(0);
        // Create a bet with zero address arbiter (anyone can be arbiter)
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            emptyArbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(2, user1[0]);

        vm.prank(user1[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(2).arbiter[0], user1[0]);
    }

    function testArbiterAcceptRole_WithMultipleAddressesInArbiterArray() public {
        address[] memory multiArbiter = new address[](2);
        multiArbiter[0] = user1[0];
        multiArbiter[1] = arbiter[0];
        // Create a bet with zero address arbiter (anyone can be arbiter)
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            multiArbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(2, arbiter[0]);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(2).arbiter[0], arbiter[0]);
    }

    function testArbiterAcceptRole_WithMultipleNullAddressInArbiterArray() public {
        address[] memory multiArbiter = new address[](3);
        multiArbiter[0] = user1[0];
        multiArbiter[2] = arbiter[0];
        // Create a bet with zero address arbiter (anyone can be arbiter)
        //expect revert Zero address in array
        vm.expectRevert(BetManagementEngine.BetManagementEngine__ZeroAddressInArrary.selector);
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            multiArbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );
    }

    /*//////////////////////////////////////////////////////////////
                        SELECT WINNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSelectWinner_MakerWins() public {
        _setupBetInProcess();

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter[0]);

        vm.expectEmit(true, true, false, false);
        emit WinnerSelected(1, true, betcaster.getBet(1));

        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(1, true);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.MAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter[0]), arbiterBalanceBefore + expectedArbiterFee);
    }

    function testSelectWinner_TakerWins() public {
        _setupBetInProcess();

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter[0]);

        vm.expectEmit(true, true, false, false);
        emit WinnerSelected(1, false, betcaster.getBet(1));

        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(1, false);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter[0]), arbiterBalanceBefore + expectedArbiterFee);
    }

    function testSelectWinner_RevertWhen_BetNotInProcess() public {
        _setupBetForArbiter(); // Bet is still WAITING_FOR_ARBITER

        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__BetNotInProcess.selector);
        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(1, true);
    }

    function testSelectWinner_RevertWhen_EndTimeNotReached() public {
        _setupBetInProcess();

        // Don't warp time - still before end time
        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__EndTimeNotReached.selector);
        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(1, true);
    }

    function testSelectWinner_RevertWhen_NotArbiter() public {
        _setupBetInProcess();

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__NotArbiter.selector);
        vm.prank(user1[0]); // Wrong arbiter
        arbiterManagementEngine.selectWinner(1, true);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullBetFlow_MakerWins() public {
        // 1. Taker accepts bet
        vm.prank(taker[0]);
        betManagementEngine.acceptBet(1);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.WAITING_FOR_ARBITER));

        // 2. Arbiter accepts role
        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(1);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.IN_PROCESS));

        // 3. Time passes
        vm.warp(block.timestamp + 2 days);

        // 4. Arbiter selects winner
        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter[0]);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(1, true);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.MAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter[0]), arbiterBalanceBefore + expectedArbiterFee);
    }

    function testFullBetFlow_TakerWins() public {
        // 1. Taker accepts bet
        vm.prank(taker[0]);
        betManagementEngine.acceptBet(1);

        // 2. Arbiter accepts role
        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // 3. Time passes
        vm.warp(block.timestamp + 2 days);

        // 4. Arbiter selects winner
        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter[0]);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(1, false);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter[0]), arbiterBalanceBefore + expectedArbiterFee);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ArbiterFeeCalculation(uint256 betAmount, uint256 arbiterFeePercent) public {
        // Bound inputs to reasonable ranges
        betAmount = bound(betAmount, 1e18, 1000000e18); // 1 to 1M tokens
        arbiterFeePercent = bound(arbiterFeePercent, 1, 1000); // 0.01% to 10%

        // Create a bet with fuzzed parameters
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            betAmount,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            arbiterFeePercent,
            BET_AGREEMENT
        );

        // Accept bet and arbiter role
        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        // Warp time and select winner
        vm.warp(block.timestamp + 2 days);

        uint256 expectedFee = (betAmount * 2) * arbiterFeePercent / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter[0]);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(2, true);

        assertEq(mockToken.balanceOf(arbiter[0]), arbiterBalanceBefore + expectedFee);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSelectWinner_WithZeroArbiterFee() public {
        // Create bet with zero arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            0,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        vm.warp(block.timestamp + 2 days);

        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter[0]);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(2, true);

        // Arbiter should receive 0 fee
        assertEq(mockToken.balanceOf(arbiter[0]), arbiterBalanceBefore);
        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.MAKER_WINS));
    }

    function testSelectWinner_WithMaxArbiterFee() public {
        uint256 maxFee = 9500; // 95%
        uint256 protocolFee = 9999 - maxFee;

        // Create bet with maximum arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            protocolFee,
            maxFee,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        uint256 betcasterStartingBalance = mockToken.balanceOf(address(betcaster));

        vm.prank(arbiter[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        vm.warp(block.timestamp + 2 days);

        uint256 expectedFee = (BET_AMOUNT * 2) * maxFee / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter[0]);

        vm.prank(arbiter[0]);
        arbiterManagementEngine.selectWinner(2, true);

        assertEq(mockToken.balanceOf(arbiter[0]), arbiterBalanceBefore + expectedFee);
        assertEq(mockToken.balanceOf(address(betcaster)), betcasterStartingBalance - expectedFee); // Verify balance of Betcaster contract
    }

    /*//////////////////////////////////////////////////////////////
                        ALLOWLIST TESTS
    //////////////////////////////////////////////////////////////*/

    function testAllowList_DefaultState() public view {
        // By default, allowlist should not be enforced
        assertEq(arbiterManagementEngine.isAllowListEnforced(), false);

        // Any address should not be on allowlist by default
        assertEq(arbiterManagementEngine.isOnAllowList(user1[0]), false);
        assertEq(arbiterManagementEngine.isOnAllowList(user2[0]), false);
        assertEq(arbiterManagementEngine.isOnAllowList(arbiter[0]), false);
    }

    function testSetAllowListStatus() public {
        // Test adding address to allowlist
        vm.prank(owner);
        arbiterManagementEngine.setAllowListStatus(user1[0], true);
        assertEq(arbiterManagementEngine.isOnAllowList(user1[0]), true);
        assertEq(arbiterManagementEngine.isOnAllowList(user2[0]), false);

        // Test removing address from allowlist
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(user1[0], false);
        assertEq(arbiterManagementEngine.isOnAllowList(user1[0]), false);
    }

    function testSetAllowListStatus_OnlyOwner() public {
        // Non-owner should not be able to set allowlist status
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1[0]));
        vm.prank(user1[0]);
        arbiterManagementEngine.setAllowListStatus(user2[0], true);
    }

    function testSetAllowListEnforcement() public {
        // Test enabling allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(true);
        assertEq(arbiterManagementEngine.isAllowListEnforced(), true);

        // Test disabling allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(false);
        assertEq(arbiterManagementEngine.isAllowListEnforced(), false);
    }

    function testSetAllowListEnforcement_OnlyOwner() public {
        // Non-owner should not be able to set enforcement
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1[0]));
        vm.prank(user1[0]);
        arbiterManagementEngine.setAllowListEnforcement(true);
    }

    function testArbiterAcceptRole_WithAllowListEnforced_AddressOnAllowList() public {
        // Enable allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(true);

        // Add user1 to allowlist
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(user1[0], true);

        // Create bet with zero address arbiter
        address[] memory emptyArbiter = new address[](1);
        emptyArbiter[0] = address(0);
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            emptyArbiter, // zero address arbiter
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        // user1 should be able to accept arbiter role (on allowlist)
        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(2, user1[0]);

        vm.prank(user1[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(2).arbiter[0], user1[0]);
    }

    function testArbiterAcceptRole_WithAllowListEnforced_AddressNotOnAllowList() public {
        // Enable allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(true);

        // user1 is not on allowlist

        // Create bet with zero address arbiter
        address[] memory emptyArbiter = new address[](1);
        emptyArbiter[0] = address(0);
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            emptyArbiter, // zero address arbiter
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        // user1 should not be able to accept arbiter role (not on allowlist)
        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__NotOnAllowList.selector);
        vm.prank(user1[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);
    }

    function testArbiterAcceptRole_WithAllowListNotEnforced() public {
        // Keep allowlist enforcement disabled (default state)
        assertEq(arbiterManagementEngine.isAllowListEnforced(), false);

        // Create bet with zero address arbiter
        address[] memory emptyArbiter = new address[](1);
        emptyArbiter[0] = address(0);
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            emptyArbiter, // zero address arbiter
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        // Any address should be able to accept arbiter role when allowlist is not enforced
        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(2, user1[0]);

        vm.prank(user1[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(2).arbiter[0], user1[0]);
    }

    function testArbiterAcceptRole_WithSpecificArbiter_AllowListNotEnforced() public {
        // Enable allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(false);

        // user1 is not on allowlist, but bet has specific arbiter (user2)
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            user2, // specific arbiter
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        // user2 should be able to accept arbiter role (specific arbiter, allowlist doesn't apply)
        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(2, user2[0]);

        vm.prank(user2[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(2).arbiter[0], user2[0]);
    }

    function testArbiterAcceptRole_WithSpecificArbiter_AllowListEnforced() public {
        // Enable allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(true);

        // user1 is not on allowlist, but bet has specific arbiter (user1)
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            user1, // specific arbiter
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        // user1 should be able to accept arbiter role (specific arbiter, allowlist doesn't apply)
        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(2, user1[0]);

        vm.prank(user1[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(2).arbiter[0], user1[0]);
    }

    function testAllowListEvents() public {
        // Test AllowListUpdated event
        vm.expectEmit(true, false, false, false);
        emit AllowListUpdated(user1[0], true);

        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(user1[0], true);

        // Test AllowListEnforcementUpdated event
        vm.expectEmit(false, false, false, false);
        emit AllowListEnforcementUpdated(true);

        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(true);
    }

    function testAllowList_EdgeCases() public {
        // Test with zero address
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(address(0), true);
        assertEq(arbiterManagementEngine.isOnAllowList(address(0)), true);

        // Test with contract address
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(address(mockToken), true);
        assertEq(arbiterManagementEngine.isOnAllowList(address(mockToken)), true);

        // Test multiple addresses
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(user1[0], true);
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(user2[0], true);
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(arbiter[0], false);

        assertEq(arbiterManagementEngine.isOnAllowList(user1[0]), true);
        assertEq(arbiterManagementEngine.isOnAllowList(user2[0]), true);
        assertEq(arbiterManagementEngine.isOnAllowList(arbiter[0]), false);
    }

    function testAllowList_IntegrationWithExistingBet() public {
        // Enable allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(true);

        // Add user1 to allowlist
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListStatus(user1[0], true);

        // Create bet with zero address arbiter
        address[] memory emptyArbiter = new address[](1);
        emptyArbiter[0] = address(0);
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            emptyArbiter, // zero address arbiter
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker[0]);
        betManagementEngine.acceptBet(2);

        // user2 should not be able to accept role (not on allowlist)
        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__NotOnAllowList.selector);
        vm.prank(user2[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        // user1 should be able to accept role
        vm.prank(user1[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        // Disable allowlist enforcement
        vm.prank(owner); // owner
        arbiterManagementEngine.setAllowListEnforcement(false);

        // Now user2 should be able to accept role
        // But bet is already in process, so it should revert
        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__BetNotWaitingForArbiter.selector);
        vm.prank(user2[0]);
        arbiterManagementEngine.ArbiterAcceptRole(2);
    }
}
