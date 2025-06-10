// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {BetTypes} from "../src/BetTypes.sol";
import {DeployBetcaster} from "../script/DeployBetcaster.s.sol";
import {ArbiterManagementEngine} from "../src/arbiterManagementEngine.sol";

contract ArbiterManagementEngineTest is Test {
    Betcaster public betcaster;
    BetManagementEngine public betManagementEngine;
    ArbiterManagementEngine public arbiterManagementEngine;
    ERC20Mock public mockToken;

    // Test addresses
    address public maker = makeAddr("maker");
    address public taker = makeAddr("taker");
    address public arbiter = makeAddr("arbiter");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    // Test constants
    uint256 public constant PROTOCOL_FEE = 100; // 1%
    uint256 public constant BET_AMOUNT = 1000e18;
    uint256 public constant ARBITER_FEE = 50; // 0.5%
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000000e18;
    string public constant BET_AGREEMENT = "Team A will win the match";

    // Events for testing
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event ArbiterAcceptedRole(uint256 indexed betNumber, address indexed arbiter);
    event WinnerSelected(uint256 indexed betNumber, address indexed winner);

    function setUp() public {
        // Deploy contracts
        DeployBetcaster deployer = new DeployBetcaster();
        address wethTokenAddr;
        (betcaster, betManagementEngine, arbiterManagementEngine, wethTokenAddr) = deployer.run();
        mockToken = new ERC20Mock();

        // Mint tokens to test addresses
        mockToken.mint(maker, INITIAL_TOKEN_SUPPLY);
        mockToken.mint(taker, INITIAL_TOKEN_SUPPLY);
        mockToken.mint(user1, INITIAL_TOKEN_SUPPLY);
        mockToken.mint(user2, INITIAL_TOKEN_SUPPLY);

        // Approve betcaster contract to spend tokens
        vm.prank(maker);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.prank(taker);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.prank(user1);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.prank(user2);
        mockToken.approve(address(betcaster), type(uint256).max);

        vm.warp(block.timestamp + 1 days);

        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, ARBITER_FEE, BET_AGREEMENT
        );
    }

    // Helper function to set up a bet ready for arbiter acceptance
    function _setupBetForArbiter() internal {
        vm.prank(taker);
        betManagementEngine.acceptBet(1);
    }

    // Helper function to set up a bet in process (arbiter has accepted)
    function _setupBetInProcess() internal {
        _setupBetForArbiter();
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);
    }

    /*//////////////////////////////////////////////////////////////
                        ARBITER ACCEPT ROLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testArbiterAcceptRole() public {
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(1, arbiter);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(1).arbiter, arbiter);
    }

    function testArbiterAcceptRole_RevertWhen_BetNotWaitingForArbiter() public {
        // Bet is still WAITING_FOR_TAKER
        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__BetNotWaitingForArbiter.selector);
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);
    }

    function testArbiterAcceptRole_RevertWhen_WrongArbiter() public {
        _setupBetForArbiter();

        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__NotArbiter.selector);
        vm.prank(user1); // Wrong arbiter
        arbiterManagementEngine.AribiterAcceptRole(1);
    }

    function testArbiterAcceptRole_WithZeroAddressArbiter() public {
        // Create a bet with zero address arbiter (anyone can be arbiter)
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, address(0), address(mockToken), BET_AMOUNT, block.timestamp + 1 days, ARBITER_FEE, BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(2);

        vm.expectEmit(true, true, false, false);
        emit ArbiterAcceptedRole(2, user1);

        vm.prank(user1);
        arbiterManagementEngine.AribiterAcceptRole(2);

        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betcaster.getBet(2).arbiter, user1);
    }

    /*//////////////////////////////////////////////////////////////
                        SELECT WINNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSelectWinner_MakerWins() public {
        _setupBetInProcess();

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        vm.expectEmit(true, true, false, false);
        emit WinnerSelected(1, maker);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.MAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore + expectedArbiterFee);
    }

    function testSelectWinner_TakerWins() public {
        _setupBetInProcess();

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        vm.expectEmit(true, true, false, false);
        emit WinnerSelected(1, taker);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, taker);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore + expectedArbiterFee);
    }

    function testSelectWinner_RevertWhen_BetNotInProcess() public {
        _setupBetForArbiter(); // Bet is still WAITING_FOR_ARBITER

        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__BetNotInProcess.selector);
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);
    }

    function testSelectWinner_RevertWhen_EndTimeNotReached() public {
        _setupBetInProcess();

        // Don't warp time - still before end time
        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__EndTimeNotReached.selector);
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);
    }

    function testSelectWinner_RevertWhen_NotArbiter() public {
        _setupBetInProcess();

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__NotArbiter.selector);
        vm.prank(user1); // Wrong arbiter
        arbiterManagementEngine.selectWinner(1, maker);
    }

    function testSelectWinner_RevertWhen_WinnerNotValid() public {
        _setupBetInProcess();

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(ArbiterManagementEngine.ArbiterManagementEngine__WinnerNotValid.selector);
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, user1); // Invalid winner
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullBetFlow_MakerWins() public {
        // 1. Taker accepts bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.WAITING_FOR_ARBITER));

        // 2. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.IN_PROCESS));

        // 3. Time passes
        vm.warp(block.timestamp + 2 days);

        // 4. Arbiter selects winner
        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.MAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore + expectedArbiterFee);
    }

    function testFullBetFlow_TakerWins() public {
        // 1. Taker accepts bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 2. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        // 3. Time passes
        vm.warp(block.timestamp + 2 days);

        // 4. Arbiter selects winner
        uint256 expectedArbiterFee = (BET_AMOUNT * 2) * ARBITER_FEE / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, taker);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));
        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore + expectedArbiterFee);
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
            taker, arbiter, address(mockToken), betAmount, block.timestamp + 1 days, arbiterFeePercent, BET_AGREEMENT
        );

        // Accept bet and arbiter role
        vm.prank(taker);
        betManagementEngine.acceptBet(2);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(2);

        // Warp time and select winner
        vm.warp(block.timestamp + 2 days);

        uint256 expectedFee = (betAmount * 2) * arbiterFeePercent / 10000;
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(2, maker);

        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore + expectedFee);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSelectWinner_WithZeroArbiterFee() public {
        // Create bet with zero arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, 0, BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(2);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(2);

        vm.warp(block.timestamp + 2 days);

        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(2, maker);

        // Arbiter should receive 0 fee
        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore);
        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.MAKER_WINS));
    }

    function testSelectWinner_WithMaxArbiterFee() public {
        uint256 maxFee = 10000; // 100%

        // Create bet with maximum arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, maxFee, BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(2);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(2);

        vm.warp(block.timestamp + 2 days);

        uint256 expectedFee = (BET_AMOUNT * 2) * maxFee / 10000; // Should be entire pot
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(2, maker);

        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore + expectedFee);
        assertEq(expectedFee, BET_AMOUNT * 2); // Verify it's the entire pot
    }
}
