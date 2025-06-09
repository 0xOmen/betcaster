// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Betcaster is Ownable {
    error Betcaster__BetAmountMustBeGreaterThanZero();
    error Betcaster__EndTimeMustBeInTheFuture();

    // Type declarations
    enum Status {
        WAITING_FOR_TAKER,
        WAITING_FOR_ARBITER,
        IN_PROCESS,
        AWAITING_ARBITRATION,
        MAKER_WINS,
        TAKER_WINS,
        CANCELLED
    }

    struct Bet {
        address maker;
        address taker;
        address arbiter;
        address betTokenAddress;
        uint256 betAmount;
        uint256 timestamp;
        uint256 endTime;
        Status status;
        uint256 arbiterFee;
        string betAgreement;
    }

    // State variables
    uint256 public s_prtocolFee;
    uint256 private s_betNumber;
    mapping(uint256 => Bet) private s_allBets;

    // Events
    event BetCreated(uint256 indexed betNumber, Bet indexed bet);

    // Modifiers
    // Constructor
    constructor(uint256 protocolFee) Ownable(msg.sender) {
        s_prtocolFee = protocolFee;
    }

    // external functions
    // public functions

    function createBet(
        address _taker,
        address _arbiter,
        address _betTokenAddress,
        uint256 _betAmount,
        uint256 _endTime,
        uint256 _arbiterFee,
        string memory _betAgreement
    ) public {
        if (_betAmount <= 0) revert Betcaster__BetAmountMustBeGreaterThanZero();
        if (_endTime <= block.timestamp) revert Betcaster__EndTimeMustBeInTheFuture();

        s_betNumber++;

        Bet memory newBet = Bet({
            maker: msg.sender,
            taker: _taker,
            arbiter: _arbiter,
            betTokenAddress: _betTokenAddress,
            betAmount: _betAmount,
            timestamp: block.timestamp,
            endTime: _endTime,
            status: Status.WAITING_FOR_TAKER,
            arbiterFee: _arbiterFee,
            betAgreement: _betAgreement
        });

        s_allBets[s_betNumber] = newBet;

        emit BetCreated(s_betNumber, newBet);

        // transfer betAmount from maker to betTokenAddress
        ERC20(_betTokenAddress).transferFrom(msg.sender, address(this), _betAmount);
    }

    // internal
    // private
    // view & pure functions

    function getCurrentBetNumber() public view returns (uint256) {
        return s_betNumber;
    }

    function getBet(uint256 _betNumber) public view returns (Bet memory) {
        return s_allBets[_betNumber];
    }
}
