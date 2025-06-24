// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using SafeERC20 for IERC20;

    error Betcaster__ProtocolPaused();
    error Betcaster__NotBetManagementEngine();
    error Betcaster__NotArbiterManagementEngine();
    error Betcaster__BetAmountCannotBeZero();
    error Betcaster__FeesCannotBeGreaterThan10000();
    error Betcaster__CannotBeZeroAddress();
    error Betcaster__BetAmountMismatch();

    // State variables
    bool private s_protocolPaused;
    uint256 public s_protocolFee;
    uint256 private s_betNumber;
    uint256 public immutable FEE_PRECISION = 10000;
    mapping(uint256 => BetTypes.Bet) private s_allBets;
    address private s_betManagementEngine;
    address private s_arbiterManagementEngine;
    address private s_prtocolFeeDepositAddress;
    uint256 private s_emergencyCancelCooldown;

    // Events
    event BetManagementEngineSet(address indexed betManagementEngine);
    event ArbiterManagementEngineSet(address indexed arbiterManagementEngine);

    // Modifiers
    modifier onlyBetManagementEngine() {
        if (s_protocolPaused) revert Betcaster__ProtocolPaused();
        if (msg.sender != s_betManagementEngine) revert Betcaster__NotBetManagementEngine();
        _;
    }

    modifier onlyArbiterManagementEngine() {
        if (s_protocolPaused) revert Betcaster__ProtocolPaused();
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
        s_protocolFee = protocolFee;
        s_protocolPaused = false;
        s_prtocolFeeDepositAddress = msg.sender;
    }

    // external functions

    // public functions
    function setBetManagementEngine(address _betManagementEngine) public onlyOwner {
        if (_betManagementEngine == address(0)) revert Betcaster__CannotBeZeroAddress();
        s_betManagementEngine = _betManagementEngine;
        emit BetManagementEngineSet(_betManagementEngine);
    }

    function setArbiterManagementEngine(address _arbiterManagementEngine) public onlyOwner {
        if (_arbiterManagementEngine == address(0)) revert Betcaster__CannotBeZeroAddress();
        s_arbiterManagementEngine = _arbiterManagementEngine;
        emit ArbiterManagementEngineSet(_arbiterManagementEngine);
    }

    function setProtocolFeeDepositAddress(address _protocolFeeDepositAddress) public onlyOwner {
        if (_protocolFeeDepositAddress == address(0)) revert Betcaster__CannotBeZeroAddress();
        s_prtocolFeeDepositAddress = _protocolFeeDepositAddress;
    }

    function pauseProtocol() public onlyOwner {
        s_protocolPaused = true;
    }

    function unpauseProtocol() public onlyOwner {
        s_protocolPaused = false;
    }

    function setProtocolFee(uint256 _protocolFee) public onlyOwner {
        if (_protocolFee >= FEE_PRECISION) revert Betcaster__FeesCannotBeGreaterThan10000();
        s_protocolFee = _protocolFee;
    }

    function setEmergencyCancelCooldown(uint256 _emergencyCancelCooldown) public onlyOwner {
        s_emergencyCancelCooldown = _emergencyCancelCooldown;
    }

    function increaseBetNumber() public onlyBetManagementEngine returns (uint256) {
        s_betNumber++;
        return s_betNumber;
    }

    function createBet(uint256 _betNumber, BetTypes.Bet memory _bet) public onlyBetManagementEngine {
        if (_bet.betAmount == 0) revert Betcaster__BetAmountCannotBeZero();
        if (_bet.arbiterFee + _bet.protocolFee >= FEE_PRECISION) revert Betcaster__FeesCannotBeGreaterThan10000();
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

    function setBetArbiterFeeToZero(uint256 _betNumber) public onlyBetManagementEngine {
        s_allBets[_betNumber].arbiterFee = 0;
    }

    function transferTokensToUser(address _user, address _betTokenAddress, uint256 _betAmount)
        public
        onlyBetManagementEngine
    {
        IERC20(_betTokenAddress).safeTransfer(_user, _betAmount);
    }

    function depositToBetcaster(address _user, address _betTokenAddress, uint256 _betAmount)
        public
        onlyBetManagementEngine
    {
        // Check that token amount deposited to the smart contract is the same as _betAmount and revert if not
        uint256 balanceBefore = IERC20(_betTokenAddress).balanceOf(address(this));
        IERC20(_betTokenAddress).safeTransferFrom(_user, address(this), _betAmount);
        uint256 balanceAfter = IERC20(_betTokenAddress).balanceOf(address(this));
        if (balanceAfter - balanceBefore != _betAmount) revert Betcaster__BetAmountMismatch();
    }

    function transferTokensToArbiter(uint256 _amount, address _arbiter, address _betTokenAddress)
        public
        onlyArbiterManagementEngine
    {
        IERC20(_betTokenAddress).safeTransfer(_arbiter, _amount);
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

    function getArbiterManagementEngine() public view returns (address) {
        return s_arbiterManagementEngine;
    }

    function getPauseStatus() public view returns (bool) {
        return s_protocolPaused;
    }

    function getEmergencyCancelCooldown() public view returns (uint256) {
        return s_emergencyCancelCooldown;
    }

    function calculateArbiterPayment(uint256 _betAmount, uint256 _arbiterFee) public pure returns (uint256) {
        return _betAmount * _arbiterFee / FEE_PRECISION;
    }

    function calculateProtocolRake(uint256 _betAmount, uint256 _protocolFee) public pure returns (uint256) {
        return _betAmount * _protocolFee / FEE_PRECISION;
    }

    function getProtocolFeeDepositAddress() public view returns (address) {
        return s_prtocolFeeDepositAddress;
    }
}
