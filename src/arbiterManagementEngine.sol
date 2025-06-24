// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    error ArbiterManagementEngine__NotOnAllowList();

    address private s_betcaster;
    mapping(address => bool) private s_allowList;
    bool private s_enforceAllowList;

    event ArbiterAcceptedRole(uint256 indexed betNumber, address indexed arbiter);
    event WinnerSelected(uint256 indexed betNumber, address indexed winner);
    event AllowListUpdated(address indexed address_, bool allowed);
    event AllowListEnforcementUpdated(bool enforced);

    constructor(address _betcaster) Ownable(msg.sender) {
        s_betcaster = _betcaster;
        s_enforceAllowList = false; // Default to not enforcing allowlist
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
            // Check allowlist if enforcement is enabled
            if (s_enforceAllowList && !s_allowList[msg.sender]) {
                revert ArbiterManagementEngine__NotOnAllowList();
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

    // Allowlist management functions
    function setAllowListStatus(address _address, bool _allowed) public onlyOwner {
        s_allowList[_address] = _allowed;
        emit AllowListUpdated(_address, _allowed);
    }

    function setAllowListEnforcement(bool _enforced) public onlyOwner {
        s_enforceAllowList = _enforced;
        emit AllowListEnforcementUpdated(_enforced);
    }

    // View functions
    function isOnAllowList(address _address) public view returns (bool) {
        return s_allowList[_address];
    }

    function isAllowListEnforced() public view returns (bool) {
        return s_enforceAllowList;
    }
}
