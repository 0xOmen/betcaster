// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {BetTypes} from "./BetTypes.sol";
import {Betcaster} from "./betcaster.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Arbiter Management Engine version 0.0.2
 * @author Betcaster
 * @notice This contract is used to manage the arbiter role for a bet.
 * It allows the arbiter to select a winner for a bet and to transfer the tokens to the arbiter.
 * It also allows the owner to set an allowlist and to enforce it.
 * It also allows the owner to set the enforcement of the allowlist.
 */
contract ArbiterManagementEngine2 is Ownable, ReentrancyGuard {
    error ArbiterManagementEngine__NotArbiter();
    error ArbiterManagementEngine__BetNotWaitingForArbiter();
    error ArbiterManagementEngine__BetNotInProcess();
    error ArbiterManagementEngine__EndTimeNotReached();
    error ArbiterManagementEngine__WinnerNotValid();
    error ArbiterManagementEngine__TakerCannotBeArbiter();
    error ArbiterManagementEngine__NotOnAllowList();

    address private immutable i_betcaster;
    mapping(address => bool) private s_allowList;
    bool private s_enforceAllowList;

    event ArbiterAcceptedRole(uint256 indexed betNumber, address indexed arbiter);
    event WinnerSelected(uint256 indexed betNumber, address indexed winner);
    event AllowListUpdated(address indexed address_, bool indexed allowed);
    event AllowListEnforcementUpdated(bool indexed enforced);

    constructor(address _betcaster) Ownable(msg.sender) {
        i_betcaster = _betcaster;
        s_enforceAllowList = false; // Default to not enforcing allowlist
    }

    /**
     * @notice Accepts the role of arbiter for a bet.
     * Taker is allowed to be arbiter. Maker cannot be arbiter or Taker.
     * There is an optional allowList that can be enforced when no arbiter is set.
     * If the allowList is enforced, only addresses on the allowList can accept the role of arbiter when set as address(0).
     * If the allowList is not enforced, anyone can accept the role of arbiter when set as address(0).
     * If the bet is already in process, the function will revert.
     * If the bet is not waiting for an arbiter, the function will revert.
     * @param _betNumber The number of the bet to accept the role for.
     */
    function ArbiterAcceptRole(uint256 _betNumber) public {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
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
            Betcaster(i_betcaster).updateBetArbiter(_betNumber, msg.sender);
        } else if (bet.arbiter != msg.sender) {
            revert ArbiterManagementEngine__NotArbiter();
        }
        emit ArbiterAcceptedRole(_betNumber, msg.sender);
        Betcaster(i_betcaster).arbiterUpdateBetStatus(_betNumber, BetTypes.Status.IN_PROCESS);
    }

    /**
     * @notice Allows Arbiter to Select a winner for a bet.
     * @param _betNumber The number of the bet to select a winner for.
     * @param _winner The address of the winner.
     */
    function selectWinner(uint256 _betNumber, address _winner) public nonReentrant {
        BetTypes.Bet memory bet = Betcaster(i_betcaster).getBet(_betNumber);
        if (bet.status != BetTypes.Status.IN_PROCESS) {
            revert ArbiterManagementEngine__BetNotInProcess();
        }
        if (bet.arbiter != msg.sender) {
            revert ArbiterManagementEngine__NotArbiter();
        }
        if (bet.maker == _winner) {
            Betcaster(i_betcaster).arbiterUpdateBetStatus(_betNumber, BetTypes.Status.MAKER_WINS);
            emit WinnerSelected(_betNumber, _winner);
        } else if (bet.taker == _winner) {
            Betcaster(i_betcaster).arbiterUpdateBetStatus(_betNumber, BetTypes.Status.TAKER_WINS);
            emit WinnerSelected(_betNumber, _winner);
        } else {
            revert ArbiterManagementEngine__WinnerNotValid();
        }
        uint256 arbiterPayment = Betcaster(i_betcaster).calculateArbiterPayment(2 * bet.betAmount, bet.arbiterFee);
        Betcaster(i_betcaster).transferTokensToArbiter(arbiterPayment, bet.arbiter, bet.betTokenAddress);
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
