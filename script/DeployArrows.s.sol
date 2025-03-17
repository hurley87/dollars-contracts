// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Arrows.sol";

/**
 * @title DeployScript
 * @notice This script deploys Arrows. Simulate running it by entering
 *         `forge script script/DeployArrows.s.sol --sender <the_caller_address>
 *         --fork-url $BASE_SEPOLIA_RPC_URL -vvvv` in the terminal. To run it for
 *         real, change it to `forge script script/DeployArrows.s.sol
 *         --fork-url $BASE_SEPOLIA_RPC_URL --broadcast`.
 */
contract DeployArrows is Script {
    function run() public {
        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        Arrows arrows = new Arrows();
        console.log("Arrows deployed at:", address(arrows));
    }
}
