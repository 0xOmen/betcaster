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
    error Betcaster__NotMaker();
    error Betcaster__BetNotWaitingForTaker();
    error Betcaster__NotMakerOrTaker();
    error Betcaster__BetNotWaitingForArbiter();
    error Betcaster__StillInCooldown();
    error Betcaster__NotTaker();
    error Betcaster__BetNotInProcess();
    error Betcaster__NotBetManagementEngine();

    // State variables
    uint256 public s_prtocolFee;
    uint256 private s_betNumber;
    mapping(uint256 => BetTypes.Bet) private s_allBets;
    address private s_betManagementEngine;

    // Events
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);

    // Modifiers
    modifier onlyBetManagementEngine() {
        if (msg.sender != s_betManagementEngine) revert Betcaster__NotBetManagementEngine();
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
    }

    function increaseBetNumber() public onlyBetManagementEngine returns (uint256) {
        s_betNumber++;
        return s_betNumber;
    }

    function createBet(uint256 _betNumber, BetTypes.Bet memory _bet) public onlyBetManagementEngine {
        s_allBets[_betNumber] = _bet;
    }

    function transferBetAmount(address _maker, address _betTokenAddress, uint256 _betAmount)
        public
        onlyBetManagementEngine
    {
        ERC20(_betTokenAddress).transferFrom(_maker, address(this), _betAmount);
    }

    function makerCancelBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = s_allBets[_betNumber];
        if (bet.maker != msg.sender) revert Betcaster__NotMaker();
        if (bet.status != BetTypes.Status.WAITING_FOR_TAKER) revert Betcaster__BetNotWaitingForTaker();
        bet.status = BetTypes.Status.CANCELLED;
        s_allBets[_betNumber].status = BetTypes.Status.CANCELLED;

        emit BetCancelled(_betNumber, msg.sender, bet);

        ERC20(bet.betTokenAddress).transfer(msg.sender, bet.betAmount);
    }

    function acceptBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = s_allBets[_betNumber];
        if (bet.status != BetTypes.Status.WAITING_FOR_TAKER) revert Betcaster__BetNotWaitingForTaker();
        if (bet.taker == address(0)) {
            bet.taker = msg.sender;
            s_allBets[_betNumber].taker = msg.sender;
        }
        if (bet.taker != msg.sender) revert Betcaster__NotTaker();
        s_allBets[_betNumber].status = BetTypes.Status.WAITING_FOR_ARBITER;

        emit BetAccepted(_betNumber, bet);

        ERC20(bet.betTokenAddress).transferFrom(msg.sender, address(this), bet.betAmount);
    }

    function noArbiterCancelBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = s_allBets[_betNumber];
        if (bet.maker != msg.sender && bet.taker != msg.sender) revert Betcaster__NotMakerOrTaker();
        if (bet.status != BetTypes.Status.WAITING_FOR_ARBITER) revert Betcaster__BetNotWaitingForArbiter();
        if (block.timestamp < bet.timestamp + 1 hours) revert Betcaster__StillInCooldown();
        bet.status = BetTypes.Status.CANCELLED;
        s_allBets[_betNumber].status = BetTypes.Status.CANCELLED;

        emit BetCancelled(_betNumber, msg.sender, bet);

        ERC20(bet.betTokenAddress).transfer(bet.maker, bet.betAmount);
        ERC20(bet.betTokenAddress).transfer(bet.taker, bet.betAmount);
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
