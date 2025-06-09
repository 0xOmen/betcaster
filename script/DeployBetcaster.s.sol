// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Betcaster} from "../src/betcaster.sol";

contract DeployBetcaster is Script {
    function run() public returns (address, address) {
        HelperConfig helperConfig = new HelperConfig();
        (address weth, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
        Betcaster betcaster = new Betcaster(100);
        vm.stopBroadcast();

        return (address(betcaster), address(weth));
    }
}
