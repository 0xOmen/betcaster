// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Betcaster} from "../src/betcaster.sol";
import {BetManagementEngine} from "../src/betManagementEngine.sol";

contract UpdateBetcaster is Script {
    function run() public returns (BetManagementEngine) {
        HelperConfig helperConfig = new HelperConfig();
        (address betcaster, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
        BetManagementEngine betManagementEngine = new BetManagementEngine(address(betcaster));
        // get betcaster contract at the predefined address
        Betcaster(betcaster).setBetManagementEngine(address(betManagementEngine));
        vm.stopBroadcast();

        return (betManagementEngine);
    }
}
