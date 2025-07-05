// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address betcaster;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 31337) {
            activeNetworkConfig = getAnvilConfig();
        } else if (block.chainid == 8453) {
            activeNetworkConfig = getBaseConfig();
        } else if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.betcaster != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock betcaster = new ERC20Mock();
        vm.stopBroadcast();
        return NetworkConfig({betcaster: address(betcaster), deployerKey: DEFAULT_ANVIL_KEY});
    }

    function getAnvilConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({betcaster: address(0), deployerKey: DEFAULT_ANVIL_KEY});
    }

    function getBaseConfig() public pure returns (NetworkConfig memory) {
        // Base mainnet WETH address
        address betcaster = 0xEA358a9670a4f2113AA17e8d6C9A0dE68c2a0aEa;
        return NetworkConfig({betcaster: betcaster, deployerKey: 0});
    }

    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        // Base Sepolia WETH address
        address betcaster = 0x117E1b87bb6bb98Be6e2a72F5E860e7F94D3e7f8;
        return NetworkConfig({betcaster: betcaster, deployerKey: 0});
    }
}
