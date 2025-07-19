// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Betcaster} from "../src/betcaster.sol";
import {ArbiterManagementEngine} from "../src/arbiterManagementEngine.sol";

contract UpdateArbiterEng is Script {
    function run() public returns (ArbiterManagementEngine) {
        HelperConfig helperConfig = new HelperConfig();
        (address betcaster, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        if (deployerKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
        }
        ArbiterManagementEngine arbiterManagementEngine = new ArbiterManagementEngine(address(betcaster));
        // get betcaster contract at the predefined address
        Betcaster(betcaster).setArbiterManagementEngine(address(arbiterManagementEngine));
        vm.stopBroadcast();

        return (arbiterManagementEngine);
    }
}
