// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";
import {ArbiterManagementEngine} from "../src/arbiterManagementEngine.sol";

contract DeployBetcaster is Script {
    uint256 public constant PROTOCOL_FEE = 50; // 0.5%

    function run() public returns (Betcaster, BetManagementEngine, ArbiterManagementEngine, address) {
        HelperConfig helperConfig = new HelperConfig();
        (address weth, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
        Betcaster betcaster = new Betcaster(PROTOCOL_FEE);
        BetManagementEngine betManagementEngine = new BetManagementEngine(address(betcaster));
        ArbiterManagementEngine arbiterManagementEngine = new ArbiterManagementEngine(address(betcaster));
        betcaster.setBetManagementEngine(address(betManagementEngine));
        betcaster.setArbiterManagementEngine(address(arbiterManagementEngine));
        vm.stopBroadcast();

        return (betcaster, betManagementEngine, arbiterManagementEngine, weth);
    }
}
