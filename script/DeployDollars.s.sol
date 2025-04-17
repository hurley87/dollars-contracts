// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Dollars.sol";

/**
 * @title DeployScript
 * @notice This script deploys Dollars. Simulate running it by entering
 *         `forge script script/DeployDollars.s.sol --sender <the_caller_address>
 *         --fork-url $BASE_SEPOLIA_RPC_URL -vvvv` in the terminal. To run it for
 *         real, change it to `forge script script/DeployDollars.s.sol
 *         --fork-url $BASE_SEPOLIA_RPC_URL --broadcast`.
 */
contract DeployDollars is Script {
    function run() public {
        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        Dollars dollars = new Dollars();
        console.log("Dollars deployed at:", address(dollars));
    }
}
