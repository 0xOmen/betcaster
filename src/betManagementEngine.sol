// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Betcaster} from "./betcaster.sol";
import {BetTypes} from "./BetTypes.sol";

/**
 * @title BetManagementEngine
 * @author 0x-Omen.eth
 *
 * BetManagementEngine handles the creation and management of bets in the Betcaster protocol.
 * It acts as the main interface for users to interact with the betting system while
 * keeping the core Betcaster contract focused on storage and state management.
 *
 * @dev This contract creates bets and delegates storage to the Betcaster contract.
 */
contract BetManagementEngine is Ownable {
    error BetManagementEngine__BetAmountMustBeGreaterThanZero();
    error BetManagementEngine__EndTimeMustBeInTheFuture();
    error BetManagementEngine__NotMaker();
    error BetManagementEngine__BetNotWaitingForTaker();
    error BetManagementEngine__NotMakerOrTaker();
    error BetManagementEngine__BetNotWaitingForArbiter();
    error BetManagementEngine__StillInCooldown();
    error BetManagementEngine__NotTaker();
    error BetManagementEngine__BetNotInProcess();

    address immutable i_betcaster;

    // Events
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    /**
     * @notice Constructor for BetManagementEngine
     * @param _betcaster The address of the Betcaster contract
     */

    constructor(address _betcaster) Ownable(msg.sender) {
        i_betcaster = _betcaster;
    }

    /**
     * @notice Creates a new bet
     * @param _taker The address of the taker (can be address(0) for open bets)
     * @param _arbiter The address of the arbiter
     * @param _betTokenAddress The address of the ERC20 token used for betting
     * @param _betAmount The amount of tokens to bet
     * @param _endTime The end time of the bet
     * @param _arbiterFee The fee to be paid to the arbiter
     * @param _betAgreement The agreement text for the bet
     */
    function createBet(
        address _taker,
        address _arbiter,
        address _betTokenAddress,
        uint256 _betAmount,
        uint256 _endTime,
        uint256 _arbiterFee,
        string memory _betAgreement
    ) public {
        if (_betAmount <= 0) revert BetManagementEngine__BetAmountMustBeGreaterThanZero();
        if (_endTime <= block.timestamp) revert BetManagementEngine__EndTimeMustBeInTheFuture();

        // Get new bet number from Betcaster
        uint256 betNumber = Betcaster(i_betcaster).increaseBetNumber();

        // Create bet struct
        BetTypes.Bet memory newBet = BetTypes.Bet({
            maker: msg.sender,
            taker: _taker,
            arbiter: _arbiter,
            betTokenAddress: _betTokenAddress,
            betAmount: _betAmount,
            timestamp: block.timestamp,
            endTime: _endTime,
            status: BetTypes.Status.WAITING_FOR_TAKER,
            arbiterFee: _arbiterFee,
            betAgreement: _betAgreement
        });

        // Store bet in Betcaster
        Betcaster(i_betcaster).createBet(betNumber, newBet);

        // Emit local event
        emit BetCreated(betNumber, newBet);

        // Transfer betAmount from maker to Betcaster contract
        Betcaster(i_betcaster).depositToBetcaster(msg.sender, _betTokenAddress, _betAmount);
    }

    function makerCancelBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        if (bet.maker != msg.sender) revert BetManagementEngine__NotMaker();
        if (bet.status != BetTypes.Status.WAITING_FOR_TAKER) revert BetManagementEngine__BetNotWaitingForTaker();
        bet.status = BetTypes.Status.CANCELLED;
        Betcaster(i_betcaster).updateBetStatus(_betNumber, bet.status);

        emit BetCancelled(_betNumber, msg.sender, bet);

        Betcaster(i_betcaster).transferToUser(msg.sender, bet.betTokenAddress, bet.betAmount);
    }

    function acceptBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        if (bet.status != BetTypes.Status.WAITING_FOR_TAKER) revert BetManagementEngine__BetNotWaitingForTaker();
        if (bet.taker == address(0)) {
            bet.taker = msg.sender;
            Betcaster(i_betcaster).updateBetTaker(_betNumber, msg.sender);
        }
        if (bet.taker != msg.sender) revert BetManagementEngine__NotTaker();
        bet.status = BetTypes.Status.WAITING_FOR_ARBITER;
        Betcaster(i_betcaster).updateBetStatus(_betNumber, bet.status);

        emit BetAccepted(_betNumber, bet);

        Betcaster(i_betcaster).depositToBetcaster(msg.sender, bet.betTokenAddress, bet.betAmount);
    }

    /**
     * @notice Gets the Betcaster contract address
     * @return The address of the Betcaster contract
     */
    function getBetcaster() public view returns (address) {
        return i_betcaster;
    }
}
