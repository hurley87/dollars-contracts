// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Warps.sol";

/**
 * @title DeployScript
 * @notice This script deploys Warps. Simulate running it by entering
 *         `forge script script/DeployWarps.s.sol --sender <the_caller_address>
 *         --fork-url $BASE_SEPOLIA_RPC_URL -vvvv` in the terminal. To run it for
 *         real, change it to `forge script script/DeployWarps.s.sol
 *         --fork-url $BASE_SEPOLIA_RPC_URL --broadcast`.
 */
contract DeployWarps is Script {
    function run() public {
        vm.broadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        Warps warps = new Warps();
        console.log("Warps deployed at:", address(warps));
    }
}
