// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine2} from "../src/betManagementEngine2.sol";

contract UpdateBetcaster is Script {
    function run() public returns (BetManagementEngine2) {
        HelperConfig helperConfig = new HelperConfig();
        (address betcaster, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
        BetManagementEngine2 betManagementEngine = new BetManagementEngine2(address(betcaster));
        // get betcaster contract at the predefined address
        Betcaster(betcaster).setBetManagementEngine(address(betManagementEngine));
        vm.stopBroadcast();

        return (betManagementEngine);
    }
}
