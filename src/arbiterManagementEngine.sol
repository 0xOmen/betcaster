// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {BetTypes} from "./BetTypes.sol";
import {Betcaster} from "./betcaster.sol";

contract ArbiterManagementEngine is Ownable {
    error ArbiterManagementEngine__NotArbiter();
    error ArbiterManagementEngine__BetNotWaitingForArbiter();
    error ArbiterManagementEngine__BetNotInProcess();
    error ArbiterManagementEngine__EndTimeNotReached();
    error ArbiterManagementEngine__WinnerNotValid();
    error ArbiterManagementEngine__TakerCannotBeArbiter();

    address private s_betcaster;

    event ArbiterAcceptedRole(uint256 indexed betNumber, address indexed arbiter);
    event WinnerSelected(uint256 indexed betNumber, address indexed winner);

    constructor(address _betcaster) Ownable(msg.sender) {
        s_betcaster = _betcaster;
    }

    function AribiterAcceptRole(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(s_betcaster).getBet(_betNumber);
        if (bet.status != BetTypes.Status.WAITING_FOR_ARBITER) {
            revert ArbiterManagementEngine__BetNotWaitingForArbiter();
        }
        if (bet.arbiter == address(0)) {
            if (bet.taker == msg.sender || bet.maker == msg.sender) {
                revert ArbiterManagementEngine__TakerCannotBeArbiter();
            }
            Betcaster(s_betcaster).updateBetArbiter(_betNumber, msg.sender);
        } else if (bet.arbiter != msg.sender) {
            revert ArbiterManagementEngine__NotArbiter();
        }
        emit ArbiterAcceptedRole(_betNumber, msg.sender);
        Betcaster(s_betcaster).arbiterUpdateBetStatus(_betNumber, BetTypes.Status.IN_PROCESS);
    }

    function selectWinner(uint256 _betNumber, address _winner) public {
        BetTypes.Bet memory bet = Betcaster(s_betcaster).getBet(_betNumber);
        if (bet.status != BetTypes.Status.IN_PROCESS) {
            revert ArbiterManagementEngine__BetNotInProcess();
        }
        if (block.timestamp < bet.endTime) {
            revert ArbiterManagementEngine__EndTimeNotReached();
        }
        if (bet.arbiter != msg.sender) {
            revert ArbiterManagementEngine__NotArbiter();
        }
        if (bet.maker == _winner) {
            Betcaster(s_betcaster).arbiterUpdateBetStatus(_betNumber, BetTypes.Status.MAKER_WINS);
            emit WinnerSelected(_betNumber, _winner);
        } else if (bet.taker == _winner) {
            Betcaster(s_betcaster).arbiterUpdateBetStatus(_betNumber, BetTypes.Status.TAKER_WINS);
            emit WinnerSelected(_betNumber, _winner);
        } else {
            revert ArbiterManagementEngine__WinnerNotValid();
        }
        uint256 arbiterPayment = Betcaster(s_betcaster).calculateArbiterPayment(2 * bet.betAmount, bet.arbiterFee);
        Betcaster(s_betcaster).transferTokensToArbiter(arbiterPayment, bet.arbiter, bet.betTokenAddress);
    }
}
