// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {BetTypes} from "../src/BetTypes.sol";
import {DeployBetcaster} from "../script/DeployBetcaster.s.sol";
import {ArbiterManagementEngine} from "../src/arbiterManagementEngine.sol";

contract BetcasterTest is Test {
    Betcaster public betcaster;
    BetManagementEngine public betManagementEngine;
    ArbiterManagementEngine public arbiterManagementEngine;
    ERC20Mock public mockToken;

    // Test addresses
    address public owner;
    address public maker = makeAddr("maker");
    address public taker = makeAddr("taker");
    address public arbiter = makeAddr("arbiter");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    // Test constants
    uint256 public constant PROTOCOL_FEE = 50; // 0.5%
    uint256 public constant BET_AMOUNT = 1000e18;
    uint256 public constant ARBITER_FEE = 100; // 1%
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000e18;
    string public constant BET_AGREEMENT = "Team A will win the match";

    // Events for testing
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);

    function setUp() public {
        // Deploy contracts
        DeployBetcaster deployer = new DeployBetcaster();
        address wethTokenAddr;
        (betcaster, betManagementEngine, arbiterManagementEngine, wethTokenAddr) = deployer.run();
        mockToken = new ERC20Mock();
        owner = betcaster.owner();

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

    function _setupBet() public {
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, ARBITER_FEE, BET_AGREEMENT
        );

        vm.prank(taker);
        betManagementEngine.acceptBet(1);

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(1);

        vm.warp(block.timestamp + 1 days);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsProtocolFee() public view {
        assertEq(betcaster.s_prtocolFee(), PROTOCOL_FEE);
    }

    function testConstructorInitializesBetNumberToZero() public view {
        assertEq(betcaster.getCurrentBetNumber(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS TESTS
    //////////////////////////////////////////////////////////////*/
    function testOnlyOwnerAccessControl() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        betcaster.setBetManagementEngine(address(betManagementEngine));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        betcaster.setArbiterManagementEngine(address(betManagementEngine));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        betcaster.setProtocolFee(100);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        betcaster.setEmergencyCancelCooldown(100);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        betcaster.pauseProtocol();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        betcaster.unpauseProtocol();
    }

    function testOnlyBetManagementEngineAccessControl() public {
        vm.expectRevert(Betcaster.Betcaster__NotBetManagementEngine.selector);
        vm.prank(user1);
        betcaster.increaseBetNumber();

        vm.expectRevert(Betcaster.Betcaster__NotBetManagementEngine.selector);
        vm.prank(user1);
        betcaster.createBet(
            1,
            BetTypes.Bet({
                maker: maker,
                taker: taker,
                arbiter: arbiter,
                betTokenAddress: address(mockToken),
                betAmount: BET_AMOUNT,
                timestamp: block.timestamp,
                endTime: block.timestamp + 1 days,
                status: BetTypes.Status.WAITING_FOR_TAKER,
                arbiterFee: ARBITER_FEE,
                betAgreement: BET_AGREEMENT
            })
        );

        _setupBet();

        vm.expectRevert(Betcaster.Betcaster__NotBetManagementEngine.selector);
        vm.prank(user1);
        betcaster.updateBetStatus(1, BetTypes.Status.WAITING_FOR_TAKER);

        vm.expectRevert(Betcaster.Betcaster__NotBetManagementEngine.selector);
        vm.prank(user1);
        betcaster.updateBetTaker(1, taker);

        vm.expectRevert(Betcaster.Betcaster__NotBetManagementEngine.selector);
        vm.prank(user1);
        betcaster.setBetArbiterFeeToZero(1);

        vm.expectRevert(Betcaster.Betcaster__NotBetManagementEngine.selector);
        vm.prank(user1);
        betcaster.transferTokensToUser(maker, address(mockToken), BET_AMOUNT);

        vm.expectRevert(Betcaster.Betcaster__NotBetManagementEngine.selector);
        vm.prank(user1);
        betcaster.depositToBetcaster(maker, address(mockToken), BET_AMOUNT);
    }

    function testOnlyArbiterManagementEngineAccessControl() public {
        _setupBet();

        vm.expectRevert(Betcaster.Betcaster__NotArbiterManagementEngine.selector);
        vm.prank(user1);
        betcaster.updateBetArbiter(1, arbiter);

        vm.expectRevert(Betcaster.Betcaster__NotArbiterManagementEngine.selector);
        vm.prank(user1);
        betcaster.arbiterUpdateBetStatus(1, BetTypes.Status.WAITING_FOR_TAKER);

        vm.expectRevert(Betcaster.Betcaster__NotArbiterManagementEngine.selector);
        vm.prank(user1);
        betcaster.transferTokensToArbiter(1, arbiter, address(mockToken));
    }

    function testProtocolPaused() public {
        _setupBet();
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, ARBITER_FEE, BET_AGREEMENT
        );

        vm.prank(owner);
        betcaster.pauseProtocol();

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, ARBITER_FEE, BET_AGREEMENT
        );

        vm.prank(owner);
        betcaster.unpauseProtocol();

        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, block.timestamp + 1 days, ARBITER_FEE, BET_AGREEMENT
        );

        vm.prank(owner);
        betcaster.pauseProtocol();

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(maker);
        betManagementEngine.makerCancelBet(2);

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(taker);
        betManagementEngine.acceptBet(2);

        vm.prank(owner);
        betcaster.unpauseProtocol();

        vm.prank(taker);
        betManagementEngine.acceptBet(2);

        vm.prank(owner);
        betcaster.pauseProtocol();

        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(taker);
        betManagementEngine.noArbiterCancelBet(2);

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(2);

        vm.prank(owner);
        betcaster.unpauseProtocol();

        vm.prank(arbiter);
        arbiterManagementEngine.AribiterAcceptRole(2);

        vm.prank(owner);
        betcaster.pauseProtocol();

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(maker);
        betManagementEngine.forfeitBet(2);

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(2, maker);

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(maker);
        betManagementEngine.emergencyCancel(2);

        vm.prank(owner);
        betcaster.unpauseProtocol();

        vm.prank(arbiter);
        arbiterManagementEngine.selectWinner(2, maker);

        vm.prank(owner);
        betcaster.pauseProtocol();

        vm.expectRevert(Betcaster.Betcaster__ProtocolPaused.selector);
        vm.prank(maker);
        betManagementEngine.claimBet(2);
    }

    ///////////////////////////////////////////////////////////////
    ////////////////////  CREATE BET TESTS   //////////////////////
    ///////////////////////////////////////////////////////////////

    function testCreateBetSuccess() public {
        uint256 endTime = block.timestamp + 1 days;

        BetTypes.Bet memory bet = BetTypes.Bet({
            maker: maker,
            taker: taker,
            arbiter: arbiter,
            betTokenAddress: address(mockToken),
            betAmount: BET_AMOUNT,
            timestamp: block.timestamp,
            endTime: endTime,
            status: BetTypes.Status.WAITING_FOR_TAKER,
            arbiterFee: ARBITER_FEE,
            betAgreement: BET_AGREEMENT
        });

        uint256 betNumber = betcaster.getCurrentBetNumber();

        vm.prank(address(betManagementEngine));
        betcaster.createBet(betNumber, bet);

        // Verify bet was created correctly
        BetTypes.Bet memory createdBet = betcaster.getBet(betNumber);
        assertEq(createdBet.maker, maker);
        assertEq(createdBet.taker, taker);
        assertEq(createdBet.arbiter, arbiter);
        assertEq(createdBet.betTokenAddress, address(mockToken));
        assertEq(createdBet.betAmount, BET_AMOUNT);
        assertEq(createdBet.timestamp, block.timestamp);
        assertEq(createdBet.endTime, endTime);
        assertEq(uint256(createdBet.status), uint256(BetTypes.Status.WAITING_FOR_TAKER));
        assertEq(createdBet.arbiterFee, ARBITER_FEE);
        assertEq(createdBet.betAgreement, BET_AGREEMENT);

        // Verify bet number incremented
        assertEq(betcaster.getCurrentBetNumber(), betNumber);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetCurrentBetNumber() public {
        uint256 endTime = block.timestamp + 1 days;
        assertEq(betcaster.getCurrentBetNumber(), 0);

        vm.prank(maker);
        betManagementEngine.createBet(
            taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT
        );

        assertEq(betcaster.getCurrentBetNumber(), 1);
    }

    function testGetBetReturnsCorrectData() public {
        BetTypes.Bet memory bet = BetTypes.Bet({
            maker: maker,
            taker: taker,
            arbiter: arbiter,
            betTokenAddress: address(mockToken),
            betAmount: BET_AMOUNT,
            timestamp: block.timestamp,
            endTime: block.timestamp + 1 days,
            status: BetTypes.Status.WAITING_FOR_TAKER,
            arbiterFee: ARBITER_FEE,
            betAgreement: BET_AGREEMENT
        });
        uint256 endTime = block.timestamp + 1 days;

        vm.prank(address(betManagementEngine));
        betcaster.createBet(1, bet);

        BetTypes.Bet memory retrievedBet = betcaster.getBet(1);

        assertEq(retrievedBet.maker, maker);
        assertEq(retrievedBet.taker, taker);
        assertEq(retrievedBet.arbiter, arbiter);
        assertEq(retrievedBet.betTokenAddress, address(mockToken));
        assertEq(retrievedBet.betAmount, BET_AMOUNT);
        assertEq(retrievedBet.endTime, endTime);
        assertEq(uint256(retrievedBet.status), uint256(BetTypes.Status.WAITING_FOR_TAKER));
        assertEq(retrievedBet.arbiterFee, ARBITER_FEE);
        assertEq(retrievedBet.betAgreement, BET_AGREEMENT);
    }

    function testGetNonExistentBetReturnsEmptyStruct() public view {
        BetTypes.Bet memory emptyBet = betcaster.getBet(999);

        assertEq(emptyBet.maker, address(0));
        assertEq(emptyBet.taker, address(0));
        assertEq(emptyBet.arbiter, address(0));
        assertEq(emptyBet.betTokenAddress, address(0));
        assertEq(emptyBet.betAmount, 0);
        assertEq(emptyBet.timestamp, 0);
        assertEq(emptyBet.endTime, 0);
        assertEq(uint256(emptyBet.status), 0);
        assertEq(emptyBet.arbiterFee, 0);
        assertEq(emptyBet.betAgreement, "");
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    /*
    function testFuzzCreateBetWithValidInputs(uint256 _betAmount, uint256 _arbiterFee, uint256 _timeOffset) public {
        // Bound inputs to valid ranges
        _betAmount = bound(_betAmount, 1, INITIAL_TOKEN_SUPPLY);
        _arbiterFee = bound(_arbiterFee, 0, 10000); // 0-100%
        _timeOffset = bound(_timeOffset, 1, 365 days);

        uint256 endTime = block.timestamp + _timeOffset;

        vm.prank(maker);
        betcaster.createBet(taker, arbiter, address(mockToken), _betAmount, endTime, _arbiterFee, BET_AGREEMENT);

        Betcaster.Bet memory createdBet = betcaster.getBet(1);
        assertEq(createdBet.betAmount, _betAmount);
        assertEq(createdBet.arbiterFee, _arbiterFee);
        assertEq(createdBet.endTime, endTime);
        assertEq(mockToken.balanceOf(address(betcaster)), _betAmount);
    }
    */
    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    /*
    function testFullBetCreationFlow() public {
        uint256 initialMakerBalance = mockToken.balanceOf(maker);
        uint256 initialContractBalance = mockToken.balanceOf(address(betcaster));
        uint256 endTime = block.timestamp + 1 days;

        // Create bet
        vm.prank(maker);
        betcaster.createBet(taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT);

        // Verify state changes
        assertEq(betcaster.getCurrentBetNumber(), 1);
        assertEq(mockToken.balanceOf(maker), initialMakerBalance - BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), initialContractBalance + BET_AMOUNT);

        // Verify bet data
        Betcaster.Bet memory bet = betcaster.getBet(1);
        assertEq(bet.maker, maker);
        assertEq(uint256(bet.status), uint256(Betcaster.Status.WAITING_FOR_TAKER));
        assertTrue(bet.timestamp <= block.timestamp);
    }

    function testFullBetAcceptanceFlow() public {
        uint256 endTime = block.timestamp + 1 days;
        uint256 initialMakerBalance = mockToken.balanceOf(maker);
        uint256 initialTakerBalance = mockToken.balanceOf(taker);

        // Create bet
        vm.prank(maker);
        betcaster.createBet(taker, arbiter, address(mockToken), BET_AMOUNT, endTime, ARBITER_FEE, BET_AGREEMENT);

        // Accept bet
        vm.prank(taker);
        betcaster.acceptBet(1);

        // Verify final state
        assertEq(mockToken.balanceOf(maker), initialMakerBalance - BET_AMOUNT);
        assertEq(mockToken.balanceOf(taker), initialTakerBalance - BET_AMOUNT);
        assertEq(mockToken.balanceOf(address(betcaster)), BET_AMOUNT * 2);
        assertEq(uint256(betcaster.getBet(1).status), uint256(Betcaster.Status.WAITING_FOR_ARBITER));
    }*/
}
