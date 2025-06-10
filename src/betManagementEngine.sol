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
    error BetManagementEngine__BetNotClaimable();
    error BetManagementEngine__BetAmountMismatch();
    error BetManagementEngine__TakerCannotBeArbiterOrMaker();

    address immutable i_betcaster;

    // Events
    event BetCreated(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetCancelled(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);
    event BetAccepted(uint256 indexed betNumber, BetTypes.Bet indexed bet);
    event BetClaimed(uint256 indexed betNumber, address indexed winner, BetTypes.Status indexed status);
    event BetForfeited(uint256 indexed betNumber, address indexed calledBy, BetTypes.Bet indexed bet);

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
        if (_taker == msg.sender || _arbiter == msg.sender) {
            revert BetManagementEngine__TakerCannotBeArbiterOrMaker();
        }

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

    /**
     * @notice Allows Maker to cancel bet if no taker has accepted.  Returns tokens to maker with no fee.
     * @param _betNumber The number of the bet to cancel
     */
    function makerCancelBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        if (bet.maker != msg.sender) revert BetManagementEngine__NotMaker();
        if (bet.status != BetTypes.Status.WAITING_FOR_TAKER) revert BetManagementEngine__BetNotWaitingForTaker();
        bet.status = BetTypes.Status.CANCELLED;
        Betcaster(i_betcaster).updateBetStatus(_betNumber, bet.status);

        emit BetCancelled(_betNumber, msg.sender, bet);

        Betcaster(i_betcaster).transferTokensToUser(msg.sender, bet.betTokenAddress, bet.betAmount);
    }

    /**
     * @notice Allows Taker to accept bet.  If bet.taker is address(0), it assigns taker to msg.sender.
     * @param _betNumber The number of the bet to accept
     */
    function acceptBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        if (bet.status != BetTypes.Status.WAITING_FOR_TAKER) revert BetManagementEngine__BetNotWaitingForTaker();
        if (bet.taker == address(0)) {
            if (bet.maker == msg.sender || bet.arbiter == msg.sender) {
                revert BetManagementEngine__TakerCannotBeArbiterOrMaker();
            }
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
     * @notice Allows Maker or Taker to cancel bet if no arbiter has been assigned.
     * Returns tokens to maker and taker with no fee.
     * @notice Must wait 1 hour after bet is created to cancel.
     * @param _betNumber The number of the bet to cancel
     */
    function noArbiterCancelBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        if (bet.maker != msg.sender && bet.taker != msg.sender) revert BetManagementEngine__NotMakerOrTaker();
        if (bet.status != BetTypes.Status.WAITING_FOR_ARBITER) revert BetManagementEngine__BetNotWaitingForArbiter();
        if (block.timestamp < bet.timestamp + 1 hours) revert BetManagementEngine__StillInCooldown();
        bet.status = BetTypes.Status.CANCELLED;
        Betcaster(i_betcaster).updateBetStatus(_betNumber, bet.status);

        emit BetCancelled(_betNumber, msg.sender, bet);

        Betcaster(i_betcaster).transferTokensToUser(bet.maker, bet.betTokenAddress, bet.betAmount);
        Betcaster(i_betcaster).transferTokensToUser(bet.taker, bet.betTokenAddress, bet.betAmount);
    }

    /**
     * @notice Allows claim bet if bet is completed. Can be called by anyone
     * @dev Sends protocol fee to owner of contract address. Does NOT send arbiter fee to arbiter which is done in arbiterManagementEngine.
     * @param _betNumber The number of the bet to claim
     */
    function claimBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        address winner;
        uint256 protocolRake = Betcaster(i_betcaster).calculateProtocolRake(2 * bet.betAmount);
        uint256 arbiterPayment = Betcaster(i_betcaster).calculateArbiterPayment(2 * bet.betAmount, bet.arbiterFee);
        uint256 winnerTake = 2 * bet.betAmount - protocolRake - arbiterPayment;
        if (protocolRake + arbiterPayment + winnerTake > 2 * bet.betAmount) {
            revert BetManagementEngine__BetAmountMismatch();
        }
        if (bet.status == BetTypes.Status.MAKER_WINS) {
            winner = bet.maker;
            bet.status = BetTypes.Status.COMPLETED_MAKER_WINS;
        } else if (bet.status == BetTypes.Status.TAKER_WINS) {
            winner = bet.taker;
            bet.status = BetTypes.Status.COMPLETED_TAKER_WINS;
        } else {
            revert BetManagementEngine__BetNotClaimable();
        }
        emit BetClaimed(_betNumber, winner, bet.status);
        Betcaster(i_betcaster).updateBetStatus(_betNumber, bet.status);
        Betcaster(i_betcaster).transferTokensToUser(winner, bet.betTokenAddress, winnerTake);
        //transfer protocol rake to owner
        Betcaster(i_betcaster).transferTokensToUser(owner(), bet.betTokenAddress, protocolRake);
    }

    /**
     * @notice Allows Maker or Taker to forfeit bet early.
     * Forfieter gives up tokens, no aribter fee is taken.
     * @notice Bet must be in process.
     * @notice sender must be maker or taker.
     * @param _betNumber The number of the bet to forfeit
     */
    function forfeitBet(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        if (bet.status != BetTypes.Status.IN_PROCESS) revert BetManagementEngine__BetNotInProcess();
        if (bet.maker == msg.sender) {
            bet.status = BetTypes.Status.TAKER_WINS;
        } else if (bet.taker == msg.sender) {
            bet.status = BetTypes.Status.MAKER_WINS;
        } else {
            revert BetManagementEngine__NotMakerOrTaker();
        }
        emit BetForfeited(_betNumber, msg.sender, bet);
        Betcaster(i_betcaster).setBetArbiterFeeToZero(_betNumber);
        Betcaster(i_betcaster).updateBetStatus(_betNumber, bet.status);
    }

    /**
     * @notice Gets the Betcaster contract address
     * @return The address of the Betcaster contract
     */
    function getBetcaster() public view returns (address) {
        return i_betcaster;
    }
}
