// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {SalaryPool} from "../src/SalaryPool.sol";
import {SelfServicePayRoll} from "../src/SelfServicePayroll.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract Deploy is Script {
    uint8 public constant PRICE_FEED_DECIMALS = 8;
    int256 public constant INITIAL_ETH_PRICE = 2000e8;

    function run()
        external
        returns (
            MockV3Aggregator priceFeed,
            SalaryPool salaryPool,
            SelfServicePayRoll payroll
        )
    {
        vm.startBroadcast();

        // Deploy mock ETH/USD price feed.
        priceFeed = new MockV3Aggregator(
            PRICE_FEED_DECIMALS,
            INITIAL_ETH_PRICE
        );

        // Deploy the ETH custody contract.
        salaryPool = new SalaryPool();

        // Deploy the payroll business-logic contract.
        payroll = new SelfServicePayRoll(
            address(priceFeed),
            address(salaryPool)
        );

        // Authorize the payroll contract to control
        // reserved payroll funds inside SalaryPool.
        salaryPool.setPayrollContract(address(payroll));

        vm.stopBroadcast();

        console2.log("========================================");
        console2.log("Government Payroll Deployment");
        console2.log("========================================");
        console2.log("Price Feed:");
        console2.logAddress(address(priceFeed));
        console2.log("Salary Pool:");
        console2.logAddress(address(salaryPool));
        console2.log("Payroll:");
        console2.logAddress(address(payroll));
        console2.log("Payroll Owner:");
        console2.logAddress(payroll.OWNER());
        console2.log("Pool Owner:");
        console2.logAddress(salaryPool.owner());
        console2.log("Payroll Contract In Pool:");
        console2.logAddress(salaryPool.payrollContract());
        console2.log("========================================");
    }
}