// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {BetTypes} from "../src/BetTypes.sol";
import {DeployBetcaster} from "../script/DeployBetcaster.s.sol";
import {ArbiterManagementEngine} from "../src/arbiterManagementEngine.sol";

contract BetManagementEngineTest is Test {
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
    uint256 public constant PROTOCOL_FEE = 50; //0.5%
    uint256 public constant BET_AMOUNT = 1000e18;
    bool public constant CAN_SETTLE_EARLY = false;
    uint256 public constant ARBITER_FEE = 100; // 1%
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000e18;
    string public constant BET_AGREEMENT = "Team A will win the match";

    // Events for testing
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet bet);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event BetClaimed(uint256 indexed betNumber, address indexed winner, BetTypes.Status indexed status);
    event BetForfeited(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet bet);

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
    }

    /*//////////////////////////////////////////////////////////////
                            CREATE BET TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateBet() public {
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

        BetTypes.Bet memory createdBet = betcaster.getBet(1);
        assertEq(betcaster.getCurrentBetNumber(), 1);
        assertEq(createdBet.maker, maker);
        assertEq(createdBet.taker, taker);
        assertEq(createdBet.arbiter, arbiter);
        assertEq(createdBet.betTokenAddress, address(mockToken));
        assertEq(createdBet.betAmount, BET_AMOUNT);
        assertEq(createdBet.protocolFee, PROTOCOL_FEE);
        assertEq(createdBet.arbiterFee, ARBITER_FEE);
        assertEq(createdBet.betAgreement, BET_AGREEMENT);
    }

    function testCreateBetRevertsWithZeroBetAmount() public {
        uint256 endTime = block.timestamp + 1 days;

        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetAmountMustBeGreaterThanZero.selector);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            0, // Zero bet amount
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );
    }

    function testCreateBetRevertsWithPastEndTime() public {
        // Advance Anvil node time by 90 minutes
        vm.warp(block.timestamp + 90 minutes);
        uint256 pastEndTime = block.timestamp - 1 hours;

        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__EndTimeMustBeInTheFuture.selector);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            pastEndTime, // Past end time
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );
    }

    function testCreateBetRevertsWithCurrentTimestamp() public {
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__EndTimeMustBeInTheFuture.selector);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp, // Current timestamp
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );
    }

    function testCreateBetRevertsWithInsufficientTokenBalance() public {
        uint256 endTime = block.timestamp + 1 days;
        address poorUser = makeAddr("poorUser");

        vm.prank(poorUser);
        vm.expectRevert(); // ERC20 transfer will revert
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );
    }

    function testCreateBetRevertsWithInsufficientAllowance() public {
        uint256 endTime = block.timestamp + 1 days;
        address userWithoutApproval = makeAddr("userWithoutApproval");
        mockToken.mint(userWithoutApproval, INITIAL_TOKEN_SUPPLY);

        vm.prank(userWithoutApproval);
        vm.expectRevert(); // ERC20 transferFrom will revert due to insufficient allowance
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MAKER CANCEL BET TESTS
    //////////////////////////////////////////////////////////////*/

    function testMakerCancelBetSuccess() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet first
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Expect BetCancelled event
        vm.expectEmit(true, true, false, false);
        emit BetCancelled(1, maker, betcaster.getBet(1));

        // Cancel bet
        vm.prank(maker);
        betManagementEngine.makerCancelBet(1);

        // Verify bet status changed
        BetTypes.Bet memory cancelledBet = betcaster.getBet(1);
        assertEq(uint256(cancelledBet.status), uint256(BetTypes.Status.CANCELLED));

        // Verify tokens were returned to maker
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), contractBalanceBefore - BET_AMOUNT);
    }

    function testMakerCancelBetRevertsWhenNotMaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Try to cancel as non-maker
        vm.prank(taker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMaker.selector);
        betManagementEngine.makerCancelBet(1);

        vm.prank(user1);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMaker.selector);
        betManagementEngine.makerCancelBet(1);
    }

    function testMakerCancelBetRevertsWhenNotWaitingForTaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create and accept bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Try to cancel after bet is accepted
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotWaitingForTaker.selector);
        betManagementEngine.makerCancelBet(1);
    }

    function testMakerCancelBetRevertsForNonExistentBet() public {
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMaker.selector);
        betManagementEngine.makerCancelBet(999);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPT BET TESTS
    //////////////////////////////////////////////////////////////*/

    function testAcceptBetSuccessWithSpecificTaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet with specific taker
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        uint256 takerBalanceBefore = mockToken.balanceOf(taker);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Expect multiple events: Transfer (from ERC20) and BetAccepted
        BetTypes.Bet memory bet = BetTypes.Bet({
            maker: maker,
            taker: taker,
            arbiter: arbiter,
            betTokenAddress: address(mockToken),
            betAmount: BET_AMOUNT,
            takerBetTokenAddress: address(mockToken),
            takerBetAmount: BET_AMOUNT,
            canSettleEarly: false,
            timestamp: block.timestamp,
            endTime: endTime,
            status: BetTypes.Status.WAITING_FOR_ARBITER,
            protocolFee: PROTOCOL_FEE,
            arbiterFee: ARBITER_FEE,
            betAgreement: BET_AGREEMENT
        });
        vm.expectEmit(true, true, false, false);
        emit BetAccepted(1, bet);
        vm.expectEmit(true, true, false, false);
        emit Transfer(taker, address(betcaster), BET_AMOUNT);

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Verify bet status changed
        BetTypes.Bet memory acceptedBet = betcaster.getBet(1);
        assertEq(uint256(acceptedBet.status), uint256(BetTypes.Status.WAITING_FOR_ARBITER));
        assertEq(acceptedBet.taker, taker);

        // Verify tokens were transferred from taker
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore - BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), contractBalanceBefore + BET_AMOUNT);
    }

    function testAcceptBetSuccessWithOpenTaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet with open taker (address(0))
        vm.prank(maker);
        betManagementEngine.createBet(
            address(0),
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        uint256 user1BalanceBefore = mockToken.balanceOf(user1);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Accept bet as user1
        vm.prank(user1);
        betManagementEngine.acceptBet(1);

        // Verify bet status and taker updated
        BetTypes.Bet memory acceptedBet = betcaster.getBet(1);
        assertEq(uint256(acceptedBet.status), uint256(BetTypes.Status.WAITING_FOR_ARBITER));
        assertEq(acceptedBet.taker, user1);

        // Verify tokens were transferred
        assertEq(mockToken.balanceOf(user1), user1BalanceBefore - BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), contractBalanceBefore + BET_AMOUNT);
    }

    function testAcceptBetRevertsWhenNotWaitingForTaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create and accept bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Try to accept again
        vm.prank(taker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotWaitingForTaker.selector);
        betManagementEngine.acceptBet(1);
    }

    function testAcceptBetRevertsWhenNotDesignatedTaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet with specific taker
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Try to accept as wrong user
        vm.prank(user1);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotTaker.selector);
        betManagementEngine.acceptBet(1);
    }

    function testAcceptBetRevertsWithInsufficientBalance() public {
        uint256 endTime = block.timestamp + 1 days;
        address poorTaker = makeAddr("poorTaker");

        // Create bet with poor taker
        vm.prank(maker);
        betManagementEngine.createBet(
            poorTaker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Try to accept without sufficient balance
        vm.prank(poorTaker);
        vm.expectRevert(); // ERC20 transfer will revert
        betManagementEngine.acceptBet(1);
    }

    /*//////////////////////////////////////////////////////////////
                        NO ARBITER CANCEL BET TESTS
    //////////////////////////////////////////////////////////////*/

    function testNoArbiterCancelBetSuccessByMaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Accept bet to set status to WAITING_FOR_ARBITER
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Verify status is now WAITING_FOR_ARBITER
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.WAITING_FOR_ARBITER));

        // Fast forward time past cooldown (1 hour)
        vm.warp(block.timestamp + 2 days);

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 takerBalanceBefore = mockToken.balanceOf(taker);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Expect BetCancelled event
        vm.expectEmit(true, true, false, false);
        emit BetCancelled(1, maker, betcaster.getBet(1));

        // Cancel bet as maker
        vm.prank(maker);
        betManagementEngine.noArbiterCancelBet(1);

        // Verify bet status changed to CANCELLED
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));

        // Verify token transfers
        // Note: There's a potential bug in the contract - it tries to transfer arbiterFee to taker
        // but the arbiterFee might be larger than what's available. Let's test what actually happens.
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), contractBalanceBefore - BET_AMOUNT - BET_AMOUNT);
    }

    function testNoArbiterCancelBetSuccessByTaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Fast forward time past cooldown
        vm.warp(block.timestamp + 2 days);

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 takerBalanceBefore = mockToken.balanceOf(taker);

        // Expect BetCancelled event
        vm.expectEmit(true, true, false, false);
        emit BetCancelled(1, taker, betcaster.getBet(1));

        // Cancel bet as taker
        vm.prank(taker);
        betManagementEngine.noArbiterCancelBet(1);

        // Verify bet status changed
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));

        // Verify token transfers
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + BET_AMOUNT);
    }

    function testNoArbiterCancelBetRevertsWhenNotMakerOrTaker() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Try to cancel as unauthorized user
        vm.prank(user1);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMakerOrTaker.selector);
        betManagementEngine.noArbiterCancelBet(1);
    }

    function testNoArbiterCancelBetRevertsWhenNotWaitingForArbiter() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet (status is WAITING_FOR_TAKER)
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Try to cancel when not in WAITING_FOR_ARBITER status
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotWaitingForArbiter.selector);
        betManagementEngine.noArbiterCancelBet(1);
    }

    function testNoArbiterCancelBetRevertsWhenStillInCooldown() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create and accept bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Fast forward only 30 minutes (less than 1 hour cooldown)
        vm.warp(block.timestamp + 30 minutes);

        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__StillInCooldown.selector);
        betManagementEngine.noArbiterCancelBet(1);
    }

    function testNoArbiterCancelBetForNonExistentBet() public {
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMakerOrTaker.selector);
        betManagementEngine.noArbiterCancelBet(999);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE BETS TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateMultipleBets() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create first bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            "First bet"
        );

        // Create second bet
        vm.prank(user1);
        betManagementEngine.createBet(
            user2,
            arbiter,
            address(mockToken),
            BET_AMOUNT / 2,
            CAN_SETTLE_EARLY,
            endTime + 1 hours,
            PROTOCOL_FEE,
            ARBITER_FEE,
            "Second bet"
        );

        // Verify both bets exist
        assertEq(betcaster.getCurrentBetNumber(), 2);

        BetTypes.Bet memory firstBet = betcaster.getBet(1);
        BetTypes.Bet memory secondBet = betcaster.getBet(2);

        assertEq(firstBet.maker, maker);
        assertEq(firstBet.betAmount, BET_AMOUNT);
        assertEq(firstBet.betAgreement, "First bet");

        assertEq(secondBet.maker, user1);
        assertEq(secondBet.betAmount, BET_AMOUNT / 2);
        assertEq(secondBet.betAgreement, "Second bet");

        // Verify contract holds both bet amounts
        assertEq(mockToken.balanceOf(address(betcaster)), BET_AMOUNT + (BET_AMOUNT / 2));
    }

    function testMultipleBetOperations() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create multiple bets
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            "Bet 1"
        );

        vm.prank(user1);
        betManagementEngine.createBet(
            user2,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            "Bet 2"
        );

        // Cancel first bet
        vm.prank(maker);
        betManagementEngine.makerCancelBet(1);

        // Accept second bet
        vm.prank(user2);
        betManagementEngine.acceptBet(2);

        // Verify states
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.WAITING_FOR_ARBITER));
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM BET TESTS
    //////////////////////////////////////////////////////////////*/

    // Helper function to set up a bet ready for claiming (maker wins)
    function _setupBetForClaimingMakerWins() internal returns (uint256 betNumber) {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        // Arbiter selects maker as winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        return 1;
    }

    // Helper function to set up a bet ready for claiming (taker wins)
    function _setupBetForClaimingTakerWins() internal returns (uint256 betNumber) {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        // Arbiter selects taker as winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, false);

        return 1;
    }

    function testClaimBet_MakerWins() public {
        _setupBetForClaimingMakerWins();

        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 expectedProtocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 expectedArbiterPayment = totalBetAmount * ARBITER_FEE / 10000;
        uint256 expectedWinnerTake = totalBetAmount - expectedProtocolRake - expectedArbiterPayment;

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 ownerBalanceBefore = mockToken.balanceOf(betManagementEngine.owner());
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Expect BetClaimed event
        vm.expectEmit(true, true, true, false);
        emit BetClaimed(1, maker, BetTypes.Status.COMPLETED_MAKER_WINS);

        // Anyone can claim the bet
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Verify bet status changed
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_MAKER_WINS));

        // Verify token transfers
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + expectedWinnerTake);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerBalanceBefore + expectedProtocolRake);

        // Contract should have less tokens (winner take + protocol rake transferred out)
        // Note: Arbiter fee was already transferred when selectWinner was called
        assertEq(
            mockToken.balanceOf(address(betcaster)), contractBalanceBefore - expectedWinnerTake - expectedProtocolRake
        );
    }

    function testClaimBet_TakerWins() public {
        _setupBetForClaimingTakerWins();

        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 expectedProtocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 expectedArbiterPayment = totalBetAmount * ARBITER_FEE / 10000;
        uint256 expectedWinnerTake = totalBetAmount - expectedProtocolRake - expectedArbiterPayment;

        uint256 takerBalanceBefore = mockToken.balanceOf(taker);
        uint256 ownerBalanceBefore = mockToken.balanceOf(betManagementEngine.owner());
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Expect BetClaimed event
        vm.expectEmit(true, true, true, false);
        emit BetClaimed(1, taker, BetTypes.Status.COMPLETED_TAKER_WINS);

        // Winner can claim their own bet
        vm.prank(taker);
        betManagementEngine.claimBet(1);

        // Verify bet status changed
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_TAKER_WINS));

        // Verify token transfers
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + expectedWinnerTake);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerBalanceBefore + expectedProtocolRake);
        assertEq(
            mockToken.balanceOf(address(betcaster)), contractBalanceBefore - expectedWinnerTake - expectedProtocolRake
        );
    }

    function testClaimBet_RevertWhen_BetNotClaimable() public {
        uint256 endTime = block.timestamp + 1 days;

        // Try to claim bet that does not exist
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotClaimable.selector);
        vm.prank(user1);
        betManagementEngine.claimBet(99);

        // Create bet but don't complete it
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Try to claim bet that's still WAITING_FOR_TAKER
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotClaimable.selector);
        vm.prank(user1);
        betManagementEngine.claimBet(1);
    }

    function testClaimBet_RevertWhen_BetInProcess() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create and accept bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // Try to claim bet that's still IN_PROCESS
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotClaimable.selector);
        vm.prank(user1);
        betManagementEngine.claimBet(1);
    }

    function testClaimBet_RevertWhen_AlreadyClaimed() public {
        _setupBetForClaimingMakerWins();

        // Claim bet once
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Try to claim again
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotClaimable.selector);
        vm.prank(user2);
        betManagementEngine.claimBet(1);
    }

    function testClaimBet_CanBeCalledByAnyone() public {
        _setupBetForClaimingMakerWins();

        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 expectedWinnerTake =
            totalBetAmount - (totalBetAmount * PROTOCOL_FEE / 10000) - (totalBetAmount * ARBITER_FEE / 10000);

        // Random user can trigger bet claim
        vm.prank(user2);
        betManagementEngine.claimBet(1);

        // Verify maker received winnings
        assertEq(mockToken.balanceOf(maker), INITIAL_TOKEN_SUPPLY - BET_AMOUNT + expectedWinnerTake);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_MAKER_WINS));
        // Verity taker received nothing
        assertEq(mockToken.balanceOf(taker), INITIAL_TOKEN_SUPPLY - BET_AMOUNT);
    }

    function testClaimBet_WithZeroProtocolFee() public {
        // Set protocol fee to 0
        vm.prank(betcaster.owner());
        betcaster.setProtocolFee(0);

        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            block.timestamp + 1 days,
            0,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        vm.warp(block.timestamp + 2 days);

        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 expectedArbiterPayment = totalBetAmount * ARBITER_FEE / 10000;
        uint256 expectedWinnerTake = totalBetAmount - expectedArbiterPayment; // No protocol fee

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 ownerBalanceBefore = mockToken.balanceOf(betManagementEngine.owner());

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        // Claim bet
        vm.prank(maker);
        betManagementEngine.claimBet(1);

        // Verify no protocol fee was taken
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + expectedWinnerTake);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerBalanceBefore); // No change
    }

    function testClaimBet_WithZeroArbiterFee() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet with zero arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, CAN_SETTLE_EARLY, endTime, PROTOCOL_FEE, 0, BET_AGREEMENT
        );

        // Complete the bet flow
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        vm.warp(block.timestamp + 2 days);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 expectedProtocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 expectedWinnerTake = totalBetAmount - expectedProtocolRake; // No arbiter fee

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 arbiterBalanceBefore = mockToken.balanceOf(arbiter);

        // Claim bet
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Verify no arbiter fee was deducted from winner take
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + expectedWinnerTake);
        // Arbiter should have received 0 additional tokens during selectWinner
        assertEq(mockToken.balanceOf(arbiter), arbiterBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM BET FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ClaimBet_CalculationAccuracy(
        uint256 betAmount,
        uint256 protocolFeePercent,
        uint256 arbiterFeePercent
    ) public {
        // Bound inputs to reasonable ranges
        betAmount = bound(betAmount, 1e18, 100000e18); // 1 to 100K tokens
        protocolFeePercent = bound(protocolFeePercent, 0, 500); // 0% to 5%
        arbiterFeePercent = bound(arbiterFeePercent, 0, 9499); // 0% to 10%

        // Ensure total fees don't exceed 100%
        vm.assume(protocolFeePercent + arbiterFeePercent <= 10000);

        vm.prank(betcaster.owner());
        betcaster.setProtocolFee(protocolFeePercent);

        // Mint sufficient tokens
        mockToken.mint(maker, betAmount * 2);
        mockToken.mint(taker, betAmount * 2);

        uint256 endTime = block.timestamp + 1 days;

        // Create bet with fuzzed parameters
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            betAmount,
            CAN_SETTLE_EARLY,
            endTime,
            protocolFeePercent,
            arbiterFeePercent,
            BET_AGREEMENT
        );

        // Complete bet flow
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        vm.warp(block.timestamp + 2 days);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        // Calculate expected amounts
        uint256 totalBetAmount = betAmount * 2;
        uint256 expectedProtocolRake = totalBetAmount * protocolFeePercent / 10000;
        uint256 expectedArbiterPayment = totalBetAmount * arbiterFeePercent / 10000;
        uint256 expectedWinnerTake = totalBetAmount - expectedProtocolRake - expectedArbiterPayment;

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 ownerBalanceBefore = mockToken.balanceOf(betManagementEngine.owner());

        // Claim bet
        vm.prank(arbiter);
        betManagementEngine.claimBet(1);

        // Verify calculations
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + expectedWinnerTake);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerBalanceBefore + expectedProtocolRake);
    }

    /*//////////////////////////////////////////////////////////////
                    CLAIM BET INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimBet_FullBetLifecycle() public {
        uint256 endTime = block.timestamp + 1 days;

        // Track initial balances
        uint256 makerInitialBalance = mockToken.balanceOf(maker);
        uint256 takerInitialBalance = mockToken.balanceOf(taker);
        uint256 arbiterInitialBalance = mockToken.balanceOf(arbiter);
        uint256 ownerInitialBalance = mockToken.balanceOf(betManagementEngine.owner());

        // 1. Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // 4. Time passes
        vm.warp(block.timestamp + 2 days);

        // 5. Arbiter selects winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        // 6. Claim bet
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Calculate expected final balances
        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 protocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 arbiterPayment = totalBetAmount * ARBITER_FEE / 10000;
        uint256 winnerTake = totalBetAmount - protocolRake - arbiterPayment;

        // Verify final balances
        assertEq(mockToken.balanceOf(maker), makerInitialBalance - BET_AMOUNT + winnerTake);
        assertEq(mockToken.balanceOf(taker), takerInitialBalance - BET_AMOUNT);
        assertEq(mockToken.balanceOf(arbiter), arbiterInitialBalance + arbiterPayment);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerInitialBalance + protocolRake);

        // Verify bet status
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_MAKER_WINS));
    }

    /*//////////////////////////////////////////////////////////////
                          FORFEIT BET TESTS
    //////////////////////////////////////////////////////////////*/

    // Helper function to set up a bet in process (ready for forfeiting)
    function _setupBetInProcess() internal returns (uint256 betNumber) {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        return 1;
    }

    function testForfeitBet_MakerForfeits() public {
        _setupBetInProcess();

        // Verify initial state
        BetTypes.Bet memory betBefore = betcaster.getBet(1);
        assertEq(uint256(betBefore.status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betBefore.arbiterFee, ARBITER_FEE);

        // Expect BetForfeited event
        vm.expectEmit(true, true, false, false);
        emit BetForfeited(1, maker, betBefore);

        // Maker forfeits bet
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Verify bet status changed to TAKER_WINS
        BetTypes.Bet memory betAfter = betcaster.getBet(1);
        assertEq(uint256(betAfter.status), uint256(BetTypes.Status.TAKER_WINS));
        assertEq(betAfter.arbiterFee, 0); // Arbiter fee should be set to zero
    }

    function testForfeitBet_TakerForfeits() public {
        _setupBetInProcess();

        // Verify initial state
        BetTypes.Bet memory betBefore = betcaster.getBet(1);
        assertEq(uint256(betBefore.status), uint256(BetTypes.Status.IN_PROCESS));
        assertEq(betBefore.arbiterFee, ARBITER_FEE);

        // Expect BetForfeited event
        vm.expectEmit(true, true, false, false);
        emit BetForfeited(1, taker, betBefore);

        // Taker forfeits bet
        vm.prank(taker);
        betManagementEngine.forfeitBet(1);

        // Verify bet status changed to MAKER_WINS
        BetTypes.Bet memory betAfter = betcaster.getBet(1);
        assertEq(uint256(betAfter.status), uint256(BetTypes.Status.MAKER_WINS));
        assertEq(betAfter.arbiterFee, 0); // Arbiter fee should be set to zero
    }

    function testForfeitBet_RevertWhen_BetNotInProcess() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet but don't put it in process
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Try to forfeit bet that's still WAITING_FOR_TAKER
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);
    }

    function testForfeitBet_RevertWhen_BetWaitingForArbiter() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create and accept bet but don't have arbiter accept
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Try to forfeit bet that's WAITING_FOR_ARBITER
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);
    }

    function testForfeitBet_RevertWhen_NotMakerOrTaker() public {
        _setupBetInProcess();

        // Try to forfeit as unauthorized user
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMakerOrTaker.selector);
        vm.prank(user1);
        betManagementEngine.forfeitBet(1);

        // Try to forfeit as arbiter
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMakerOrTaker.selector);
        vm.prank(arbiter);
        betManagementEngine.forfeitBet(1);
    }

    function testForfeitBet_RevertWhen_BetAlreadyCompleted() public {
        _setupBetInProcess();

        // Maker forfeits first
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Try to forfeit again when bet is already in TAKER_WINS status
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(taker);
        betManagementEngine.forfeitBet(1);
    }

    function testForfeitBet_ArbiterFeeSetToZero() public {
        _setupBetInProcess();

        // Verify arbiter fee is initially set
        BetTypes.Bet memory betBefore = betcaster.getBet(1);
        assertEq(betBefore.arbiterFee, ARBITER_FEE);
        assertTrue(betBefore.arbiterFee > 0);

        // Forfeit bet
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Verify arbiter fee is now zero
        BetTypes.Bet memory betAfter = betcaster.getBet(1);
        assertEq(betAfter.arbiterFee, 0);
    }

    function testForfeitBet_WithHighArbiterFee() public {
        uint256 highArbiterFee = 1000; // 10%
        uint256 endTime = block.timestamp + 1 days;

        // Create bet with high arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            highArbiterFee,
            BET_AGREEMENT
        );

        // Complete bet setup
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // Verify high arbiter fee is set
        assertEq(betcaster.getBet(1).arbiterFee, highArbiterFee);

        // Forfeit bet
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Verify arbiter fee is set to zero regardless of initial value
        assertEq(betcaster.getBet(1).arbiterFee, 0);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));
    }

    /*//////////////////////////////////////////////////////////////
                    FORFEIT BET INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testForfeitBet_FullWorkflowMakerForfeits() public {
        uint256 endTime = block.timestamp + 1 days;

        // Track initial balances
        uint256 makerInitialBalance = mockToken.balanceOf(maker);
        uint256 takerInitialBalance = mockToken.balanceOf(taker);
        uint256 arbiterInitialBalance = mockToken.balanceOf(arbiter);
        uint256 ownerInitialBalance = mockToken.balanceOf(betManagementEngine.owner());

        // 1. Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // 4. Maker forfeits
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // 5. Claim bet (taker wins)
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Calculate expected final balances (no arbiter fee since it was forfeited)
        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 protocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 winnerTake = totalBetAmount - protocolRake; // No arbiter fee

        // Verify final balances
        assertEq(mockToken.balanceOf(maker), makerInitialBalance - BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), takerInitialBalance - BET_AMOUNT + winnerTake);
        assertEq(mockToken.balanceOf(arbiter), arbiterInitialBalance); // No arbiter fee
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerInitialBalance + protocolRake);

        // Verify bet status
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_TAKER_WINS));
    }

    function testForfeitBet_FullWorkflowTakerForfeits() public {
        uint256 endTime = block.timestamp + 1 days;

        // Track initial balances
        uint256 makerInitialBalance = mockToken.balanceOf(maker);
        uint256 takerInitialBalance = mockToken.balanceOf(taker);
        uint256 arbiterInitialBalance = mockToken.balanceOf(arbiter);
        uint256 ownerInitialBalance = mockToken.balanceOf(betManagementEngine.owner());

        // 1. Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // 4. Taker forfeits
        vm.prank(taker);
        betManagementEngine.forfeitBet(1);

        // 5. Claim bet (maker wins)
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Calculate expected final balances (no arbiter fee since it was forfeited)
        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 protocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 winnerTake = totalBetAmount - protocolRake; // No arbiter fee

        // Verify final balances
        assertEq(mockToken.balanceOf(maker), makerInitialBalance - BET_AMOUNT + winnerTake);
        assertEq(mockToken.balanceOf(taker), takerInitialBalance - BET_AMOUNT);
        assertEq(mockToken.balanceOf(arbiter), arbiterInitialBalance); // No arbiter fee
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerInitialBalance + protocolRake);

        // Verify bet status
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_MAKER_WINS));
    }

    function testForfeitBet_CompareWithNormalWin() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create two identical bets
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(maker);
        betManagementEngine.createBet(
            user2,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Set up both bets identically
        vm.prank(taker);
        betManagementEngine.acceptBet(1);
        vm.prank(user2);
        betManagementEngine.acceptBet(2);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(2);

        // First bet: forfeit
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Second bet: normal arbiter decision
        vm.warp(block.timestamp + 2 days);
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(2, false);

        // Compare arbiter fees
        assertEq(betcaster.getBet(1).arbiterFee, 0); // Forfeited bet has no arbiter fee
        assertEq(betcaster.getBet(2).arbiterFee, ARBITER_FEE); // Normal bet keeps arbiter fee

        // Claim both bets
        vm.prank(user1);
        betManagementEngine.claimBet(1);
        vm.prank(user1);
        betManagementEngine.claimBet(2);

        // Verify different payout structures
        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 protocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 arbiterPayment = totalBetAmount * ARBITER_FEE / 10000;

        // Forfeited bet: winner gets more (no arbiter fee)
        uint256 forfeitWinnerTake = totalBetAmount - protocolRake;
        // Normal bet: winner gets less (arbiter fee deducted)
        uint256 normalWinnerTake = totalBetAmount - protocolRake - arbiterPayment;

        assertTrue(forfeitWinnerTake > normalWinnerTake);
    }

    /*//////////////////////////////////////////////////////////////
                        FORFEIT BET EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testForfeitBet_WithZeroProtocolAndArbiterFee() public {
        uint256 endTime = block.timestamp + 1 days;
        vm.prank(betcaster.owner());
        betcaster.setProtocolFee(0);

        // Create bet with zero arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, CAN_SETTLE_EARLY, endTime, 0, 0, BET_AGREEMENT
        );

        // Complete bet setup
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // Verify arbiter fee is already zero
        assertEq(betcaster.getBet(1).arbiterFee, 0);

        // Forfeit bet
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Verify arbiter fee remains zero and status changed
        assertEq(betcaster.getBet(1).arbiterFee, 0);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));

        vm.prank(taker);
        betManagementEngine.claimBet(1);

        // Verify protocol fee is deducted
        assertEq(mockToken.balanceOf(maker), INITIAL_TOKEN_SUPPLY - BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), INITIAL_TOKEN_SUPPLY + BET_AMOUNT);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), 0);
    }

    function testForfeitBet_EventEmission() public {
        _setupBetInProcess();

        BetTypes.Bet memory bet = betcaster.getBet(1);

        BetTypes.Bet memory betBefore = BetTypes.Bet({
            maker: bet.maker,
            taker: bet.taker,
            arbiter: bet.arbiter,
            betTokenAddress: bet.betTokenAddress,
            betAmount: bet.betAmount,
            takerBetTokenAddress: bet.takerBetTokenAddress,
            takerBetAmount: bet.takerBetAmount,
            canSettleEarly: bet.canSettleEarly,
            timestamp: bet.timestamp,
            endTime: bet.endTime,
            arbiterFee: bet.arbiterFee,
            protocolFee: bet.protocolFee,
            betAgreement: bet.betAgreement,
            status: BetTypes.Status.TAKER_WINS
        });

        // Test exact event emission
        vm.expectEmit(true, true, false, true);
        emit BetForfeited(1, maker, betBefore);

        vm.prank(maker);
        betManagementEngine.forfeitBet(1);
    }

    /*//////////////////////////////////////////////////////////////
                      FORFEIT BET FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ForfeitBet_WithVariousArbiterFees(uint256 arbiterFeePercent) public {
        // Bound arbiter fee to valid range
        arbiterFeePercent = bound(arbiterFeePercent, 0, 9999); // 0% to 95%
        uint256 protocolFeePercent = 9999 - arbiterFeePercent; // 0% to 95%
        vm.prank(betcaster.owner());
        betcaster.setProtocolFee(protocolFeePercent);

        uint256 endTime = block.timestamp + 1 days;

        // Create bet with fuzzed arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            protocolFeePercent,
            arbiterFeePercent,
            BET_AGREEMENT
        );

        // Complete bet setup
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // Verify initial arbiter fee
        assertEq(betcaster.getBet(1).arbiterFee, arbiterFeePercent);

        // Forfeit bet
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Verify arbiter fee is always set to zero regardless of initial value
        assertEq(betcaster.getBet(1).arbiterFee, 0);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));

        vm.prank(taker);
        betManagementEngine.claimBet(1);

        uint256 expectedProtocolFee = BET_AMOUNT * 2 * (protocolFeePercent) / 10000;

        // Verify protocol fee is deducted
        assertEq(mockToken.balanceOf(maker), INITIAL_TOKEN_SUPPLY - BET_AMOUNT);
        assertEq(
            mockToken.balanceOf(taker),
            INITIAL_TOKEN_SUPPLY + BET_AMOUNT
                - (BET_AMOUNT * 2 * (protocolFeePercent + betcaster.getBet(1).arbiterFee) / 10000)
        );
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), expectedProtocolFee);
    }

    /*//////////////////////////////////////////////////////////////
                      EMERGENCY CANCEL BET TESTS
    //////////////////////////////////////////////////////////////*/

    // Helper function to set up a bet ready for emergency cancellation
    function _setupBetForEmergencyCancel() internal returns (uint256 betNumber) {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Arbiter accepts role (bet becomes IN_PROCESS)
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        return 1;
    }

    function testEmergencyCancel_SuccessByMaker() public {
        // Set emergency cancel cooldown to 1 hour
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Warp past bet end time + cooldown
        vm.warp(block.timestamp + 1 days + 1 hours + 1 minutes);

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 takerBalanceBefore = mockToken.balanceOf(taker);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Expect BetCancelled event
        vm.expectEmit(true, true, false, false);
        emit BetCancelled(1, maker, betcaster.getBet(1));

        // Emergency cancel by maker
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Verify bet status changed to CANCELLED
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));

        // Verify tokens returned to both parties
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), contractBalanceBefore - (BET_AMOUNT * 2));
    }

    function testEmergencyCancel_SuccessByTaker() public {
        _setupBetForEmergencyCancel();

        // Warp past bet end time + cooldown
        vm.warp(block.timestamp + 30 days + 2 hours + 1 minutes);

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 takerBalanceBefore = mockToken.balanceOf(taker);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(betcaster));

        // Expect BetCancelled event
        vm.expectEmit(true, true, false, false);
        emit BetCancelled(1, taker, betcaster.getBet(1));

        // Emergency cancel by taker
        vm.prank(taker);
        betManagementEngine.emergencyCancel(1);

        // Verify bet status changed to CANCELLED
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));

        // Verify tokens returned to both parties
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), contractBalanceBefore - (BET_AMOUNT * 2));
    }

    function testEmergencyCancel_RevertWhen_BetNotInProcess() public {
        uint256 endTime = block.timestamp + 1 days;

        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        // Create bet but don't put it in process
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Warp past cooldown period
        vm.warp(block.timestamp + 1 days + 1 hours + 1 minutes);

        // Try to emergency cancel bet that's still WAITING_FOR_TAKER
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);
    }

    function testEmergencyCancel_RevertWhen_BetWaitingForArbiter() public {
        uint256 endTime = block.timestamp + 1 days;

        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        // Create and accept bet but don't have arbiter accept
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Warp past cooldown period
        vm.warp(block.timestamp + 1 days + 1 hours + 1 minutes);

        // Try to emergency cancel bet that's WAITING_FOR_ARBITER
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);
    }

    function testEmergencyCancel_RevertWhen_NotMakerOrTaker() public {
        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Warp past cooldown period
        vm.warp(block.timestamp + 1 days + 1 hours + 1 minutes);

        // Try to emergency cancel as unauthorized user
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMakerOrTaker.selector);
        vm.prank(user1);
        betManagementEngine.emergencyCancel(1);

        // Try to emergency cancel as arbiter
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMakerOrTaker.selector);
        vm.prank(arbiter);
        betManagementEngine.emergencyCancel(1);
    }

    function testEmergencyCancel_RevertWhen_StillInCooldown() public {
        // Set emergency cancel cooldown to 2 hours
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(2 hours);

        _setupBetForEmergencyCancel();

        // Warp to just before cooldown expires
        vm.warp(block.timestamp + 1 days + 2 hours - 1 minutes);

        // Try to emergency cancel while still in cooldown
        vm.expectRevert(BetManagementEngine.BetManagementEngine__StillInCooldown.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);
    }

    function testEmergencyCancel_RevertWhen_BetEndTimeNotReached() public {
        // Set emergency cancel cooldown to 1 hour
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Try to emergency cancel before bet end time
        vm.expectRevert(BetManagementEngine.BetManagementEngine__StillInCooldown.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);
    }

    function testEmergencyCancel_WithZeroCooldown() public {
        // Set emergency cancel cooldown to 0
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(0);

        _setupBetForEmergencyCancel();

        // Warp to exactly bet end time (no additional cooldown)
        vm.warp(block.timestamp + 1 days);

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 takerBalanceBefore = mockToken.balanceOf(taker);

        // Emergency cancel should work immediately after bet end time
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Verify success
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + BET_AMOUNT);
    }

    function testEmergencyCancel_WithLongCooldown() public {
        // Set emergency cancel cooldown to 7 days
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(7 days);

        _setupBetForEmergencyCancel();

        // Warp to just before long cooldown expires
        vm.warp(block.timestamp + 1 days + 7 days - 1 minutes);

        // Should still revert
        vm.expectRevert(BetManagementEngine.BetManagementEngine__StillInCooldown.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Warp past long cooldown
        vm.warp(block.timestamp + 2 minutes);

        // Should now succeed
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
    }

    function testEmergencyCancel_RevertWhen_BetAlreadyCompleted() public {
        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Complete the bet normally first
        vm.warp(block.timestamp + 1 days + 1 minutes);
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        // Warp past cooldown period
        vm.warp(block.timestamp + 1 hours + 1 minutes);

        // Try to emergency cancel already completed bet
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);
    }

    function testEmergencyCancel_RevertWhen_BetAlreadyForfeited() public {
        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Forfeit the bet first
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Warp past cooldown period
        vm.warp(block.timestamp + 1 days + 1 hours + 1 minutes);

        // Try to emergency cancel already forfeited bet
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(taker);
        betManagementEngine.emergencyCancel(1);
    }

    /*//////////////////////////////////////////////////////////////
                  EMERGENCY CANCEL INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testEmergencyCancel_FullWorkflow() public {
        uint256 endTime = block.timestamp + 1 days;

        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        // Track initial balances
        uint256 makerInitialBalance = mockToken.balanceOf(maker);
        uint256 takerInitialBalance = mockToken.balanceOf(taker);
        uint256 arbiterInitialBalance = mockToken.balanceOf(arbiter);
        uint256 ownerInitialBalance = mockToken.balanceOf(betManagementEngine.owner());

        // 1. Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // 4. Time passes beyond bet end time + cooldown
        vm.warp(endTime + 1 hours + 1 minutes);

        // 5. Emergency cancel by taker
        vm.prank(taker);
        betManagementEngine.emergencyCancel(1);

        // Verify final balances - both parties get their money back
        assertEq(mockToken.balanceOf(maker), makerInitialBalance);
        assertEq(mockToken.balanceOf(taker), takerInitialBalance);
        assertEq(mockToken.balanceOf(arbiter), arbiterInitialBalance); // No change
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerInitialBalance); // No change

        // Verify bet status
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
    }

    function testEmergencyCancel_CompareWithNormalCancel() public {
        uint256 endTime = block.timestamp + 1 days;

        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(2 hours);

        // Create two identical bets
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        vm.prank(maker);
        betManagementEngine.createBet(
            user2,
            arbiter,
            address(mockToken),
            BET_AMOUNT,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Accept both bets
        vm.prank(taker);
        betManagementEngine.acceptBet(1);
        vm.prank(user2);
        betManagementEngine.acceptBet(2);

        // Only first bet gets arbiter
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // First bet: emergency cancel (IN_PROCESS)
        vm.warp(endTime + 2 hours + 1 minutes);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Second bet: normal no arbiter cancel (WAITING_FOR_ARBITER)
        vm.warp(block.timestamp + 1 hours); // Past the 1 hour cooldown for noArbiterCancel
        vm.prank(maker);
        betManagementEngine.noArbiterCancelBet(2);

        // Both bets should be cancelled with tokens returned
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
        assertEq(uint256(betcaster.getBet(2).status), uint256(BetTypes.Status.CANCELLED));

        // Both makers should get their tokens back
        uint256 expectedMakerBalance = INITIAL_TOKEN_SUPPLY; // Back to original balance
        assertEq(mockToken.balanceOf(maker), expectedMakerBalance);
    }

    function testEmergencyCancel_EventEmission() public {
        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Warp past cooldown
        vm.warp(block.timestamp + 1 days + 1 hours + 1 minutes);

        BetTypes.Bet memory bet = betcaster.getBet(1);

        BetTypes.Bet memory betBefore = BetTypes.Bet({
            maker: bet.maker,
            taker: bet.taker,
            arbiter: bet.arbiter,
            betTokenAddress: bet.betTokenAddress,
            betAmount: bet.betAmount,
            takerBetTokenAddress: bet.takerBetTokenAddress,
            takerBetAmount: bet.takerBetAmount,
            canSettleEarly: bet.canSettleEarly,
            timestamp: bet.timestamp,
            endTime: bet.endTime,
            arbiterFee: bet.arbiterFee,
            protocolFee: bet.protocolFee,
            betAgreement: bet.betAgreement,
            status: BetTypes.Status.CANCELLED
        });

        // Test exact event emission
        vm.expectEmit(true, true, false, true);
        emit BetCancelled(1, maker, betBefore);

        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY CANCEL EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testEmergencyCancel_ExactCooldownBoundary() public {
        // Set emergency cancel cooldown to 1 hour
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Warp to exactly when cooldown expires
        vm.warp(block.timestamp + 1 days + 1 hours);

        // Should succeed at exact boundary
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
    }

    function testEmergencyCancel_MultipleAttempts() public {
        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        _setupBetForEmergencyCancel();

        // Try too early
        vm.expectRevert(BetManagementEngine.BetManagementEngine__StillInCooldown.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Try still too early
        vm.warp(block.timestamp + 1 days + 30 minutes);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__StillInCooldown.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Finally succeed
        vm.warp(block.timestamp + 31 minutes);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Try again after successful cancel
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotInProcess.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
    }

    /*//////////////////////////////////////////////////////////////
                  EMERGENCY CANCEL FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_EmergencyCancel_WithVariousCooldowns(uint256 cooldownHours) public {
        // Bound cooldown to reasonable range (0 to 30 days)
        cooldownHours = bound(cooldownHours, 0, 720);
        uint256 cooldownSeconds = cooldownHours * 1 hours;

        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(cooldownSeconds);

        _setupBetForEmergencyCancel();

        // Try to cancel before cooldown expires (should fail if cooldown > 0)
        if (cooldownSeconds > 0) {
            vm.warp(block.timestamp + 1 days + cooldownSeconds - 1 minutes);
            vm.expectRevert(BetManagementEngine.BetManagementEngine__StillInCooldown.selector);
            vm.prank(maker);
            betManagementEngine.emergencyCancel(1);
        }

        // Warp past cooldown and try again (should succeed)
        vm.warp(block.timestamp + 1 days + cooldownSeconds + 1 minutes);

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 takerBalanceBefore = mockToken.balanceOf(taker);

        vm.prank(maker);
        betManagementEngine.emergencyCancel(1);

        // Verify success
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + BET_AMOUNT);
    }

    function testFuzz_EmergencyCancel_WithVariousBetAmounts(uint256 betAmount) public {
        // Bound bet amount to reasonable range
        betAmount = bound(betAmount, 1e18, 100000e18);

        // Set emergency cancel cooldown
        vm.prank(betcaster.owner());
        betcaster.setEmergencyCancelCooldown(1 hours);

        // Mint sufficient tokens
        mockToken.mint(maker, betAmount * 2);
        mockToken.mint(taker, betAmount * 2);

        uint256 endTime = block.timestamp + 1 days;

        // Create bet with fuzzed amount
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            betAmount,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // Complete bet setup
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // Warp past cooldown
        vm.warp(endTime + 1 hours + 1 minutes);

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 takerBalanceBefore = mockToken.balanceOf(taker);

        // Emergency cancel
        vm.prank(taker);
        betManagementEngine.emergencyCancel(1);

        // Verify correct amounts returned
        assertEq(mockToken.balanceOf(maker), makerBalanceBefore + betAmount);
        assertEq(mockToken.balanceOf(taker), takerBalanceBefore + betAmount);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.CANCELLED));
    }

    function testFuzz_PrecisionLossWithSmallBetSize(uint256 betAmount) public {
        // Bound bet amount to reasonable range
        betAmount = bound(betAmount, 1, 100);

        uint256 endTime = block.timestamp + 1 days;

        // Track initial balances
        uint256 makerInitialBalance = mockToken.balanceOf(maker);
        uint256 takerInitialBalance = mockToken.balanceOf(taker);
        uint256 arbiterInitialBalance = mockToken.balanceOf(arbiter);
        uint256 ownerInitialBalance = mockToken.balanceOf(betManagementEngine.owner());

        // 1. Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            betAmount,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // 4. Time passes
        vm.warp(block.timestamp + 2 days);

        // 5. Arbiter selects winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        // 6. Claim bet
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Calculate expected final balances
        uint256 totalBetAmount = betAmount * 2;
        uint256 protocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 arbiterPayment = totalBetAmount * ARBITER_FEE / 10000;
        uint256 winnerTake = totalBetAmount - protocolRake - arbiterPayment;

        // Verify final balances
        assertEq(mockToken.balanceOf(maker), makerInitialBalance - betAmount + winnerTake);
        assertEq(mockToken.balanceOf(taker), takerInitialBalance - betAmount);
        assertEq(mockToken.balanceOf(arbiter), arbiterInitialBalance + arbiterPayment);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerInitialBalance + protocolRake);

        // Verify bet status
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_MAKER_WINS));
    }

    /*//////////////////////////////////////////////////////////////
                  FUZZ TESTS VARIOUS TOKEN AMOUNTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_CreateBet_WithVariousTokenAmounts(uint256 betAmount) public {
        // Bound bet amount to reasonable range
        betAmount = bound(betAmount, 1, 1e6);

        uint256 endTime = block.timestamp + 1 days;

        // Track initial balances
        uint256 makerInitialBalance = mockToken.balanceOf(maker);
        uint256 takerInitialBalance = mockToken.balanceOf(taker);
        uint256 arbiterInitialBalance = mockToken.balanceOf(arbiter);
        uint256 ownerInitialBalance = mockToken.balanceOf(betManagementEngine.owner());

        // 1. Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker,
            arbiter,
            address(mockToken),
            betAmount,
            CAN_SETTLE_EARLY,
            endTime,
            PROTOCOL_FEE,
            ARBITER_FEE,
            BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.ArbiterAcceptRole(1);

        // 4. Time passes
        vm.warp(block.timestamp + 2 days);

        // 5. Arbiter selects winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, true);

        // 6. Claim bet
        vm.prank(user1);
        betManagementEngine.claimBet(1);

        // Calculate expected final balances
        uint256 totalBetAmount = betAmount * 2;
        uint256 protocolRake = totalBetAmount * PROTOCOL_FEE / 10000;
        uint256 arbiterPayment = totalBetAmount * ARBITER_FEE / 10000;
        uint256 winnerTake = totalBetAmount - protocolRake - arbiterPayment;

        // Verify final balances
        assertEq(mockToken.balanceOf(maker), makerInitialBalance - betAmount + winnerTake);
        assertEq(mockToken.balanceOf(taker), takerInitialBalance - betAmount);
        assertEq(mockToken.balanceOf(arbiter), arbiterInitialBalance + arbiterPayment);
        assertEq(mockToken.balanceOf(betManagementEngine.owner()), ownerInitialBalance + protocolRake);

        // Verify bet status
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.COMPLETED_MAKER_WINS));
    }

    /*//////////////////////////////////////////////////////////////
                    CHANGE BET PARAMETERS TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeBetParametersSuccess() public {
        // Create initial bet
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

        // New parameters
        address newTaker = user1;
        address newArbiter = user2;
        bool newCanSettleEarly = true;
        uint256 newEndTime = block.timestamp + 2 days;
        string memory newAgreement = "New agreement text";

        // Change parameters
        vm.prank(maker);
        betManagementEngine.changeBetParameters(1, newTaker, newArbiter, newCanSettleEarly, newEndTime, newAgreement);

        // Verify changes
        BetTypes.Bet memory updatedBet = betcaster.getBet(1);
        assertEq(updatedBet.taker, newTaker);
        assertEq(updatedBet.arbiter, newArbiter);
        assertEq(updatedBet.canSettleEarly, newCanSettleEarly);
        assertEq(updatedBet.endTime, newEndTime);
        assertEq(updatedBet.betAgreement, newAgreement);
    }

    function testChangeBetParametersRevertsWhenNotMaker() public {
        // Create initial bet
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

        // Try to change parameters as non-maker
        vm.prank(taker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__NotMaker.selector);
        betManagementEngine.changeBetParameters(
            1, user1, user2, CAN_SETTLE_EARLY, block.timestamp + 2 days, "New agreement"
        );
    }

    function testChangeBetParametersRevertsWhenNotWaitingForTaker() public {
        // Create and accept bet
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

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Try to change parameters after bet is accepted
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__BetNotWaitingForTaker.selector);
        betManagementEngine.changeBetParameters(
            1, user1, user2, CAN_SETTLE_EARLY, block.timestamp + 2 days, "New agreement"
        );
    }

    function testChangeBetParametersRevertsWithPastEndTime() public {
        vm.warp(block.timestamp + 1 days);
        // Create initial bet
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

        // Try to change to past end time
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__EndTimeMustBeInTheFuture.selector);
        betManagementEngine.changeBetParameters(
            1, user1, user2, CAN_SETTLE_EARLY, block.timestamp - 1 hours, "New agreement"
        );
    }

    function testChangeBetParametersRevertsWithCurrentTimestamp() public {
        // Create initial bet
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

        // Try to change to current timestamp
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__EndTimeMustBeInTheFuture.selector);
        betManagementEngine.changeBetParameters(1, user1, user2, CAN_SETTLE_EARLY, block.timestamp, "New agreement");
    }

    function testChangeBetParametersRevertsWithMakerAsTakerOrArbiter() public {
        // Create initial bet
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

        // Try to set maker as taker
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__TakerCannotBeArbiterOrMaker.selector);
        betManagementEngine.changeBetParameters(
            1,
            maker, // maker as taker
            user2,
            CAN_SETTLE_EARLY,
            block.timestamp + 2 days,
            "New agreement"
        );

        // Try to set maker as arbiter
        vm.prank(maker);
        vm.expectRevert(BetManagementEngine.BetManagementEngine__TakerCannotBeArbiterOrMaker.selector);
        betManagementEngine.changeBetParameters(
            1,
            user1,
            maker, // maker as arbiter
            CAN_SETTLE_EARLY,
            block.timestamp + 2 days,
            "New agreement"
        );
    }
}
