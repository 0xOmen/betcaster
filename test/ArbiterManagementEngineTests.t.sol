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
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000000e18;
    string public constant BET_AGREEMENT = "Team A will win the match";

    // Events for testing
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event ArbiterAcceptedRole(uint256 indexed betNumber, address indexed arbiter);

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
}
