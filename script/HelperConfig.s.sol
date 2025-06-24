// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address weth;
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
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock weth = new ERC20Mock();
        vm.stopBroadcast();
        return NetworkConfig({weth: address(weth), deployerKey: DEFAULT_ANVIL_KEY});
    }

    function getAnvilConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({weth: address(0), deployerKey: DEFAULT_ANVIL_KEY});
    }

    function getBaseConfig() public pure returns (NetworkConfig memory) {
        // Base mainnet WETH address
        return NetworkConfig({weth: address(0x4200000000000000000000000000000000000006), deployerKey: 0});
    }

    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        // Base Sepolia WETH address
        return NetworkConfig({weth: address(0x4200000000000000000000000000000000000006), deployerKey: 0});
    }
}
