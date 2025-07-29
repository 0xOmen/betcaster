// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BetTypes
 * @author 0x-Omen.eth
 * @notice Shared types and enums for the Betcaster protocol
 */
library BetTypes {
    /**
     * @notice Status is the current state of the bet.
     * @dev WAITING_FOR_TAKER - The bet is waiting for a taker to accept the bet.
     * @dev WAITING_FOR_ARBITER - The bet is waiting for an arbiter to accept their role.
     * @dev IN_PROCESS - All parties have agreed to the bet and are waiting for end time and arbitration.
     * @dev AWAITING_ARBITRATION - The bet is awaiting arbitration.
     * @dev MAKER_WINS - The maker has won the bet.
     * @dev TAKER_WINS - The taker has won the bet.
     * @dev COMPLETED_MAKER_WINS - The the maker has won and claimed their winnings.
     * @dev COMPLETED_TAKER_WINS - The the taker has won and claimed their winnings.
     * @dev CANCELLED - The bet has been cancelled by one or more parties.
     */
    enum Status {
        WAITING_FOR_TAKER,
        WAITING_FOR_ARBITER,
        IN_PROCESS,
        AWAITING_ARBITRATION,
        MAKER_WINS,
        TAKER_WINS,
        COMPLETED_MAKER_WINS,
        COMPLETED_TAKER_WINS,
        CANCELLED
    }

    struct Bet {
        address maker;
        address[] taker;
        address[] arbiter;
        address betTokenAddress;
        uint256 betAmount;
        address takerBetTokenAddress;
        uint256 takerBetAmount;
        bool canSettleEarly;
        uint256 timestamp;
        uint256 takerDeadline;
        uint256 endTime;
        Status status;
        uint256 protocolFee;
        uint256 arbiterFee;
        string betAgreement;
    }
}
