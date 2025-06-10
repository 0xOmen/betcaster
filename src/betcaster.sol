// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {BetTypes} from "./BetTypes.sol";

/**
 * @title Betcaster
 * @author 0x-Omen.eth
 *
 * Betcaster is a Peer to Peer escrow protocol utilizing Trusted Arbiters to resolve outcomes.
 * It is highly configurable to allow for a wide range of use cases.
 * The Protocol takes a fee from each bet to cover protocol costs.
 * Arbiters fees are set by the maker and are paid to the arbiter at the end of the bet.
 *
 * @dev This is the main contract that stores the state of every agreement.
 */
contract Betcaster is Ownable {
    error Betcaster__BetNotWaitingForTaker();
    error Betcaster__NotMakerOrTaker();
    error Betcaster__BetNotWaitingForArbiter();
    error Betcaster__StillInCooldown();
    error Betcaster__NotTaker();
    error Betcaster__BetNotInProcess();
    error Betcaster__NotBetManagementEngine();
    error Betcaster__NotArbiterManagementEngine();
    error Betcaster__BetAmountCannotBeZero();
    error Betcaster__ArbiterFeeCannotBeGreaterThan10000();

    // State variables
    uint256 public s_prtocolFee;
    uint256 private s_betNumber;
    mapping(uint256 => BetTypes.Bet) private s_allBets;
    address private s_betManagementEngine;
    address private s_arbiterManagementEngine;

    // Events
    event BetManagementEngineSet(address indexed betManagementEngine);
    event ArbiterManagementEngineSet(address indexed arbiterManagementEngine);

    // Modifiers
    modifier onlyBetManagementEngine() {
        if (msg.sender != s_betManagementEngine) revert Betcaster__NotBetManagementEngine();
        _;
    }

    modifier onlyArbiterManagementEngine() {
        if (msg.sender != s_arbiterManagementEngine) revert Betcaster__NotArbiterManagementEngine();
        _;
    }

    // Constructor
    /**
     * @notice constructor is called at contract creation.
     * @dev Owner is automatically set to deployer.
     * @param protocolFee The fee taken from each bet to cover protocol costs (100 = 1%)
     */
    constructor(uint256 protocolFee) Ownable(msg.sender) {
        s_prtocolFee = protocolFee;
    }

    // external functions

    // public functions
    function setBetManagementEngine(address _betManagementEngine) public onlyOwner {
        s_betManagementEngine = _betManagementEngine;
        emit BetManagementEngineSet(_betManagementEngine);
    }

    function setArbiterManagementEngine(address _arbiterManagementEngine) public onlyOwner {
        s_arbiterManagementEngine = _arbiterManagementEngine;
        emit ArbiterManagementEngineSet(_arbiterManagementEngine);
    }

    function increaseBetNumber() public onlyBetManagementEngine returns (uint256) {
        s_betNumber++;
        return s_betNumber;
    }

    function createBet(uint256 _betNumber, BetTypes.Bet memory _bet) public onlyBetManagementEngine {
        if (_bet.betAmount == 0) revert Betcaster__BetAmountCannotBeZero();
        if (_bet.arbiterFee > 10000) revert Betcaster__ArbiterFeeCannotBeGreaterThan10000();
        s_allBets[_betNumber] = _bet;
    }

    function updateBetStatus(uint256 _betNumber, BetTypes.Status _status) public onlyBetManagementEngine {
        s_allBets[_betNumber].status = _status;
    }

    function arbiterUpdateBetStatus(uint256 _betNumber, BetTypes.Status _status) public onlyArbiterManagementEngine {
        s_allBets[_betNumber].status = _status;
    }

    function updateBetTaker(uint256 _betNumber, address _taker) public onlyBetManagementEngine {
        s_allBets[_betNumber].taker = _taker;
    }

    function updateBetArbiter(uint256 _betNumber, address _arbiter) public onlyArbiterManagementEngine {
        s_allBets[_betNumber].arbiter = _arbiter;
    }

    function transferTokensToUser(address _user, address _betTokenAddress, uint256 _betAmount)
        public
        onlyBetManagementEngine
    {
        ERC20(_betTokenAddress).transfer(_user, _betAmount);
    }

    function depositToBetcaster(address _user, address _betTokenAddress, uint256 _betAmount)
        public
        onlyBetManagementEngine
    {
        ERC20(_betTokenAddress).transferFrom(_user, address(this), _betAmount);
    }

    function transferTokensToArbiter(uint256 _betAmount, address _arbiter, address _betTokenAddress)
        public
        onlyArbiterManagementEngine
    {
        ERC20(_betTokenAddress).transfer(_arbiter, _betAmount);
    }

    // internal
    // private
    // view & pure functions

    function getCurrentBetNumber() public view returns (uint256) {
        return s_betNumber;
    }

    function getBet(uint256 _betNumber) public view returns (BetTypes.Bet memory) {
        return s_allBets[_betNumber];
    }

    function getBetManagementEngine() public view returns (address) {
        return s_betManagementEngine;
    }
}
