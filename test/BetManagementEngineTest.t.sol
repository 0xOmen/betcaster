// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {BetTypes} from "../src/BetTypes.sol";
import {DeployBetcaster} from "../script/DeployBetcaster.s.sol";

contract BetManagementEngineTest is Test {
    Betcaster public betcaster;
    BetManagementEngine public betManagementEngine;
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
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000e18;
    string public constant BET_AGREEMENT = "Team A will win the match";

    // Events for testing
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        // Deploy contracts
        DeployBetcaster deployer = new DeployBetcaster();
        address wethTokenAddr;
        (betcaster, betManagementEngine, wethTokenAddr) = deployer.run();
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
}
