// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";

contract DeployBetcaster is Script {
    function run() public returns (address, address, address) {
        HelperConfig helperConfig = new HelperConfig();
        (address weth, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
        Betcaster betcaster = new Betcaster(100);
        BetManagementEngine betManagementEngine = new BetManagementEngine(msg.sender, address(betcaster));
        betcaster.setBetManagementEngine(address(betManagementEngine));
        vm.stopBroadcast();

        return (address(betcaster), address(betManagementEngine), address(weth));
    }
}
