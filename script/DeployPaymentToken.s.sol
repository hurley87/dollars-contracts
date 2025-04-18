// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17; // Match the pragma of PaymentToken

import "forge-std/Script.sol";
import "../src/PaymentToken.sol";

/**
 * @title DeployPaymentToken
 * @notice This script deploys the PaymentToken contract.
 *         It requires the DEPLOYER_ADDRESS and DEPLOYER_PRIVATE_KEY environment variables.
 *         Simulate running it by entering:
 *         `forge script script/DeployPaymentToken.s.sol --sender $(forge-get-addr $DEPLOYER_PRIVATE_KEY) --fork-url $BASE_SEPOLIA_RPC_URL -vvvv`
 *         To run it for real, change it to:
 *         `forge script script/DeployPaymentToken.s.sol --fork-url $BASE_SEPOLIA_RPC_URL --broadcast`
 */
contract DeployPaymentToken is Script {
    function run() public {
        address deployerAddress = 0xBe523e724B9Ea7D618dD093f14618D90c4B19b0c;
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        require(deployerAddress != address(0), "DeployPaymentToken: DEPLOYER_ADDRESS env var not set");
        require(deployerPrivateKey != 0, "DeployPaymentToken: DEPLOYER_PRIVATE_KEY env var not set");

        vm.startBroadcast(deployerPrivateKey);

        PaymentToken paymentToken = new PaymentToken(deployerAddress);

        vm.stopBroadcast();

        console.log("PaymentToken deployed at:", address(paymentToken));
        console.log("Initial owner (and recipient of initial supply):", deployerAddress);
    }
}
