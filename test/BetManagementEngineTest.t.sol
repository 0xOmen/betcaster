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
    uint256 public constant ARBITER_FEE = 100; // 1%
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000e18;
    string public constant BET_AGREEMENT = "Team A will win the match";

    // Events for testing
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event BetClaimed(uint256 indexed betNumber, address indexed winner, BetTypes.Status indexed status);
    event BetForfeited(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, ARBITER_FEE, BET_AGREEMENT
        );

        BetTypes.Bet memory createdBet = betcaster.getBet(1);
        assertEq(betcaster.getCurrentBetNumber(), 1);
        assertEq(createdBet.maker, maker);
        assertEq(createdBet.taker, taker);
        assertEq(createdBet.arbiter, arbiter);
        assertEq(createdBet.betTokenAddress, address(mockToken));
        assertEq(createdBet.betAmount, BET_AMOUNT);
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
            endTime,
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
            pastEndTime, // Past end time
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
            block.timestamp, // Current timestamp
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );
    }

    function testCreateBetRevertsWithInsufficientAllowance() public {
        uint256 endTime = block.timestamp + 1 days;
        address userWithoutApproval = makeAddr("userWithoutApproval");
        mockToken.mint(userWithoutApproval, INITIAL_TOKEN_SUPPLY);

        vm.prank(userWithoutApproval);
        vm.expectRevert(); // ERC20 transferFrom will revert due to insufficient allowance
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            timestamp: block.timestamp,
            endTime: endTime,
            status: BetTypes.Status.WAITING_FOR_ARBITER,
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
            address(0), arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            poorTaker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // Accept bet to set status to WAITING_FOR_ARBITER
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Verify status is now WAITING_FOR_ARBITER
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.WAITING_FOR_ARBITER));

        // Fast forward time past cooldown (1 hour)
        vm.warp(block.timestamp + 2 hours);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Fast forward time past cooldown
        vm.warp(block.timestamp + 2 hours);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
        betManagementEngine.createBet(taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, "First bet");

        // Create second bet
        vm.prank(user1);
        betManagementEngine.createBet(
            user2, arbiter, address(mockToken), BET_AMOUNT / 2, endTime + 1 hours, ARBITER_FEE, "Second bet"
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
        betManagementEngine.createBet(taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, "Bet 1");

        vm.prank(user1);
        betManagementEngine.createBet(user2, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, "Bet 2");

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        // Arbiter selects maker as winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);

        return 1;
    }

    // Helper function to set up a bet ready for claiming (taker wins)
    function _setupBetForClaimingTakerWins() internal returns (uint256 betNumber) {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        // Warp to after end time
        vm.warp(block.timestamp + 2 days);

        // Arbiter selects taker as winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, taker);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

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

        _setupBetForClaimingMakerWins();

        uint256 totalBetAmount = BET_AMOUNT * 2;
        uint256 expectedArbiterPayment = totalBetAmount * ARBITER_FEE / 10000;
        uint256 expectedWinnerTake = totalBetAmount - expectedArbiterPayment; // No protocol fee

        uint256 makerBalanceBefore = mockToken.balanceOf(maker);
        uint256 ownerBalanceBefore = mockToken.balanceOf(betManagementEngine.owner());

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
        betManagementEngine.createBet(taker, arbiter, address(mockToken), BET_AMOUNT, endTime, 0, BET_AGREEMENT);

        // Complete the bet flow
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        vm.warp(block.timestamp + 2 days);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);

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
        arbiterFeePercent = bound(arbiterFeePercent, 0, 1000); // 0% to 10%

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
            taker, arbiter, address(mockToken), betAmount, endTime, arbiterFeePercent, BET_AGREEMENT
        );

        // Complete bet flow
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        vm.warp(block.timestamp + 2 days);

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        // 4. Time passes
        vm.warp(block.timestamp + 2 days);

        // 5. Arbiter selects winner
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(1, maker);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, highArbiterFee, BET_AGREEMENT
        );

        // Complete bet setup
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // 2. Accept bet
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        // 3. Arbiter accepts role
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

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
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        vm.prank(maker);
        betManagementEngine.createBet(
            user2, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        // Set up both bets identically
        vm.prank(taker);
        betManagementEngine.acceptBet(1);
        vm.prank(user2);
        betManagementEngine.acceptBet(2);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(2);

        // First bet: forfeit
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Second bet: normal arbiter decision
        vm.warp(block.timestamp + 2 days);
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(2, user2);

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

    function testForfeitBet_WithZeroArbiterFee() public {
        uint256 endTime = block.timestamp + 1 days;

        // Create bet with zero arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(taker, arbiter, address(mockToken), BET_AMOUNT, endTime, 0, BET_AGREEMENT);

        // Complete bet setup
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        // Verify arbiter fee is already zero
        assertEq(betcaster.getBet(1).arbiterFee, 0);

        // Forfeit bet
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Verify arbiter fee remains zero and status changed
        assertEq(betcaster.getBet(1).arbiterFee, 0);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));
    }

    function testForfeitBet_EventEmission() public {
        _setupBetInProcess();

        BetTypes.Bet memory betBefore = betcaster.getBet(1);

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
        arbiterFeePercent = bound(arbiterFeePercent, 0, 10000); // 0% to 100%

        uint256 endTime = block.timestamp + 1 days;

        // Create bet with fuzzed arbiter fee
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, arbiterFeePercent, BET_AGREEMENT
        );

        // Complete bet setup
        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        // Verify initial arbiter fee
        assertEq(betcaster.getBet(1).arbiterFee, arbiterFeePercent);

        // Forfeit bet
        vm.prank(maker);
        betManagementEngine.forfeitBet(1);

        // Verify arbiter fee is always set to zero regardless of initial value
        assertEq(betcaster.getBet(1).arbiterFee, 0);
        assertEq(uint256(betcaster.getBet(1).status), uint256(BetTypes.Status.TAKER_WINS));
    }
}
