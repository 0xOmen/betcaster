// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {BetTypes} from "./BetTypes.sol";
import {Betcaster} from "./betcaster.sol";

contract ArbiterManagementEngine is Ownable {
    error ArbiterManagementEngine__NotArbiter();
    error ArbiterManagementEngine__BetNotWaitingForArbiter();

    address private s_betcaster;

    event ArbiterAcceptedRole(uint256 indexed betNumber, address indexed arbiter);

    constructor(address _betcaster) Ownable(msg.sender) {
        s_betcaster = _betcaster;
    }

    function AribiterAcceptRole(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(s_betcaster).getBet(_betNumber);
        if (bet.status != BetTypes.Status.WAITING_FOR_ARBITER) {
            revert ArbiterManagementEngine__BetNotWaitingForArbiter();
        }
        if (bet.arbiter == address(0)) {
            Betcaster(s_betcaster).updateBetArbiter(_betNumber, msg.sender);
        } else if (bet.arbiter != msg.sender) {
            revert ArbiterManagementEngine__NotArbiter();
        }
        emit ArbiterAcceptedRole(_betNumber, msg.sender);
        Betcaster(s_betcaster).arbiterUpdateBetStatus(_betNumber, BetTypes.Status.IN_PROCESS);
    }
}
