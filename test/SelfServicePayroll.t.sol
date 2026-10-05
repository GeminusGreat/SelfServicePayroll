// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SalaryPool} from "../src/SalaryPool.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {SelfServicePayRoll,BudgetAlreadySet} from "../src/SelfServicePayroll.sol";

contract SelfServicePayrollTest is Test {
    SelfServicePayRoll public payroll;
    SalaryPool public salaryPool;
    MockV3Aggregator public priceFeed;

    address public employee;
    address public secondEmployee;
    address public unauthorizedUser;

    uint256 public constant ETH_PRICE = 2000e8;

    function setUp() public {
        // ---------------------------------------------------------
        // Deploy mock ETH/USD price feed
        // ---------------------------------------------------------

        priceFeed = new MockV3Aggregator(
            8,
            int256(ETH_PRICE)
        );

        // ---------------------------------------------------------
        // Deploy SalaryPool
        // ---------------------------------------------------------

        salaryPool = new SalaryPool();

        // ---------------------------------------------------------
        // Deploy SelfServicePayRoll
        // ---------------------------------------------------------

        payroll = new SelfServicePayRoll(
            address(priceFeed),
            address(salaryPool)
        );

        // ---------------------------------------------------------
        // Connect SalaryPool to payroll
        // ---------------------------------------------------------

        salaryPool.setPayrollContract(
            address(payroll)
        );

        // ---------------------------------------------------------
        // Test accounts
        // ---------------------------------------------------------

        employee = makeAddr("employee");
        secondEmployee = makeAddr("secondEmployee");
        unauthorizedUser = makeAddr("unauthorizedUser");

        // ---------------------------------------------------------
        // Fund SalaryPool
        // ---------------------------------------------------------

        vm.deal(
            address(salaryPool),
            10 ether
        );
    }

    // =============================================================
    //                         DEPLOYMENT
    // =============================================================

    function testOwnerIsDeployer() public view {
        assertEq(
            payroll.OWNER(),
            address(this)
        );
    }

    function testPriceFeedIsCorrect() public view {
        assertEq(
            address(payroll.PRICEFEED()),
            address(priceFeed)
        );
    }

    function testSalaryPoolIsCorrect() public view {
        assertEq(
            address(payroll.SALARYPOOL()),
            address(salaryPool)
        );
    }

    function testInitialPayrollPeriod() public view {
        assertEq(
            payroll.payrollPeriod(),
            1
        );
    }

    // =============================================================
    //                       SALARY LEVELS
    // =============================================================

    function testInitialSalaryLevels() public view {
        assertEq(
            payroll.salaryByLevel(1),
            100e18
        );

        assertEq(
            payroll.salaryByLevel(2),
            170e18
        );

        assertEq(
            payroll.salaryByLevel(3),
            320e18
        );

        assertEq(
            payroll.salaryByLevel(4),
            650e18
        );
    }

    function testOwnerCanUpdateSalary() public {
        payroll.setSalary(1, 200);

        assertEq(
            payroll.salaryByLevel(1),
            200e18
        );
    }

    function testNonOwnerCannotUpdateSalary() public {
        vm.prank(unauthorizedUser);

        vm.expectRevert();

        payroll.setSalary(1, 200);
    }

    function testCannotSetInvalidSalaryLevel() public {
        vm.expectRevert();

        payroll.setSalary(5, 200);
    }

    // =============================================================
    //                    EMPLOYEE REGISTRATION
    // =============================================================

    function testEmployeeCanRegister() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        (
            string memory name,
            string memory ministry,
            uint8 level,
            address wallet,
            bool isSuspended,
            uint8 deductionPercent,
            uint256 deductionPeriod,
            uint256 lastPaidPeriod,
            bool registered
        ) = payroll.employees("STAFF001");

        assertEq(name, "John Doe");
        assertEq(ministry, "Ministry of Finance");
        assertEq(level, 1);
        assertEq(wallet, employee);
        assertFalse(isSuspended);
        assertEq(deductionPercent, 0);
        assertEq(deductionPeriod, 0);
        assertEq(lastPaidPeriod, 0);
        assertTrue(registered);

        assertEq(
            payroll.employeeCount(),
            1
        );
    }

    function testEmployeeStaffIdIsMappedToWallet() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        assertEq(
            payroll.addressToStaffId(employee),
            "STAFF001"
        );
    }

    function testEmployeeCanGetOwnStaffId() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        vm.prank(employee);

        assertEq(
            payroll.myStaffId(),
            "STAFF001"
        );
    }

    function testCannotRegisterDuplicateStaffId() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        vm.prank(secondEmployee);

        vm.expectRevert();

        payroll.registerEmployee(
            "STAFF001",
            "Jane Doe",
            "Ministry of Health",
            1
        );
    }

    function testCannotRegisterSameWalletTwice() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        vm.prank(employee);

        vm.expectRevert();

        payroll.registerEmployee(
            "STAFF002",
            "John Doe",
            "Ministry of Finance",
            1
        );
    }

    function testCannotRegisterInvalidLevel() public {
        vm.prank(employee);

        vm.expectRevert();

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            5
        );
    }

    function testCannotRegisterEmptyStaffId() public {
        vm.prank(employee);

        vm.expectRevert();

        payroll.registerEmployee(
            "",
            "John Doe",
            "Ministry of Finance",
            1
        );
    }

    // =============================================================
    //                         BUDGET
    // =============================================================

    function testOwnerCanSetBudget() public {
        payroll.setBudget(100);

        assertEq(
            payroll.budget(),
            100e18
        );

        assertTrue(
            payroll.budgetSet()
        );
    }

    function testSettingBudgetReservesEth() public {
        payroll.setBudget(100);

        /*
         * ETH = $2,000
         *
         * $100 / $2,000 = 0.05 ETH
         */

        assertEq(
            salaryPool.reservedFunds(),
            0.05 ether
        );
    }

    function testRequiredEthForBudget() public {
        payroll.setBudget(100);

        assertEq(
            payroll.requiredEthForBudget(),
            0.05 ether
        );
    }

    function testNonOwnerCannotSetBudget() public {
        vm.prank(unauthorizedUser);

        vm.expectRevert();

        payroll.setBudget(100);
    }

    // =============================================================
    //                       SALARY CLAIM
    // =============================================================

    function testEmployeeCanClaimSalary() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        // Level 1 salary = $100.
        payroll.setBudget(100);

        uint256 employeeBalanceBefore =
            employee.balance;

        vm.prank(employee);

        payroll.claimSalary();

        /*
         * ETH price = $2,000
         *
         * Salary = $100
         *
         * $100 / $2,000 = 0.05 ETH
         */

        assertEq(
            employee.balance,
            employeeBalanceBefore + 0.05 ether
        );
    }

    function testSalaryClaimReducesReservedFunds() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.setBudget(100);

        vm.prank(employee);

        payroll.claimSalary();

        assertEq(
            salaryPool.reservedFunds(),
            0
        );
    }

    function testSalaryClaimReducesBudget() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.setBudget(200);

        vm.prank(employee);

        payroll.claimSalary();

        assertEq(
            payroll.budget(),
            100e18
        );
    }

    function testEmployeesPaidIncreasesAfterClaim() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.setBudget(100);

        vm.prank(employee);

        payroll.claimSalary();

        assertEq(
            payroll.employeesPaid(),
            1
        );
    }

    function testEmployeeCannotClaimTwiceInSamePeriod() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.setBudget(200);

        vm.prank(employee);

        payroll.claimSalary();

        vm.prank(employee);

        vm.expectRevert();

        payroll.claimSalary();
    }

    function testUnregisteredEmployeeCannotClaim() public {
        payroll.setBudget(100);

        vm.prank(unauthorizedUser);

        vm.expectRevert();

        payroll.claimSalary();
    }

    // =============================================================
    //                         SUSPENSION
    // =============================================================

    function testOwnerCanSuspendEmployee() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.suspendEmployee(
            "STAFF001"
        );

        (
            ,
            ,
            ,
            ,
            bool isSuspended,
            ,
            ,
            ,
            
        ) = payroll.employees("STAFF001");

        assertTrue(isSuspended);
    }

    function testSuspendedEmployeeCannotClaim() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.setBudget(100);

        payroll.suspendEmployee(
            "STAFF001"
        );

        vm.prank(employee);

        vm.expectRevert();

        payroll.claimSalary();
    }

    function testOwnerCanUnsuspendEmployee() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.suspendEmployee(
            "STAFF001"
        );

        payroll.unsuspendEmployee(
            "STAFF001"
        );

        (
            ,
            ,
            ,
            ,
            bool isSuspended,
            ,
            ,
            ,
            
        ) = payroll.employees("STAFF001");

        assertFalse(isSuspended);
    }

    // =============================================================
    //                         DEDUCTIONS
    // =============================================================

    function testSalaryCutIsApplied() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        /*
         * Level 1 salary = $100
         *
         * 50% deduction = $50
         *
         * Employee receives $50.
         */

        payroll.cutSalary(
            "STAFF001",
            50
        );

        payroll.setBudget(100);

        uint256 employeeBalanceBefore =
            employee.balance;

        vm.prank(employee);

        payroll.claimSalary();

        assertEq(
            employee.balance,
            employeeBalanceBefore + 0.025 ether
        );
    }

    function testCannotSetDeductionAbove100Percent() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        vm.expectRevert();

        payroll.cutSalary(
            "STAFF001",
            101
        );
    }

    function testOwnerCanResetPenalty() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.cutSalary(
            "STAFF001",
            50
        );

        payroll.resetPenalty(
            "STAFF001"
        );

        (
            ,
            ,
            ,
            ,
            ,
            uint8 deductionPercent,
            ,
            ,
            
        ) = payroll.employees("STAFF001");

        assertEq(
            deductionPercent,
            0
        );
    }

    // =============================================================
    //                    PAYROLL PERIOD
    // =============================================================

    function testStartNewPayrollIncrementsPeriod() public {
        assertEq(
            payroll.payrollPeriod(),
            1
        );

        payroll.startNewPayroll();

        assertEq(
            payroll.payrollPeriod(),
            2
        );
    }

    function testStartNewPayrollReleasesReservedFunds() public {
        payroll.setBudget(100);

        assertEq(
            salaryPool.reservedFunds(),
            0.05 ether
        );

        payroll.startNewPayroll();

        assertEq(
            salaryPool.reservedFunds(),
            0
        );
    }

    function testStartNewPayrollResetsBudget() public {
        payroll.setBudget(100);

        payroll.startNewPayroll();

        assertEq(
            payroll.budget(),
            0
        );

        assertFalse(
            payroll.budgetSet()
        );
    }

    function testStartNewPayrollResetsEmployeesPaid() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        payroll.setBudget(100);

        vm.prank(employee);

        payroll.claimSalary();

        assertEq(
            payroll.employeesPaid(),
            1
        );

        payroll.startNewPayroll();

        assertEq(
            payroll.employeesPaid(),
            0
        );
    }

    // =============================================================
    //                       PRICE FEED
    // =============================================================

    function testLatestEthPrice() public view {
        assertEq(
            payroll.getLatestEthPriceUsd(),
            2000e18
        );
    }

    function testPoolBalanceInUsd() public view {
        /*
         * Pool contains 10 ETH.
         *
         * ETH price = $2,000.
         *
         * 10 ETH = $20,000.
         */

        assertEq(
            payroll.getContractBalanceInUsd(),
            20_000e18
        );
    }

    // =============================================================
    //                         MULTIPLE
    //                         EMPLOYEES
    // =============================================================

    function testMultipleEmployeesCanClaim() public {
        vm.prank(employee);

        payroll.registerEmployee(
            "STAFF001",
            "John Doe",
            "Ministry of Finance",
            1
        );

        vm.prank(secondEmployee);

        payroll.registerEmployee(
            "STAFF002",
            "Jane Doe",
            "Ministry of Health",
            1
        );

        /*
         * Two employees × $100 = $200.
         */

        payroll.setBudget(200);

        vm.prank(employee);

        payroll.claimSalary();

        vm.prank(secondEmployee);

        payroll.claimSalary();

        assertEq(
            employee.balance,
            0.05 ether
        );

        assertEq(
            secondEmployee.balance,
            0.05 ether
        );

        assertEq(
            payroll.employeesPaid(),
            2
        );

        assertEq(
            payroll.budget(),
            0
        );

        assertEq(
            salaryPool.reservedFunds(),
            0
        );
    }

    function testCannotSetBudgetTwiceInSamePayroll() public {
    payroll.setBudget(1000);

    vm.expectRevert(BudgetAlreadySet.selector);
    payroll.setBudget(2000);
}

function testBudgetConversionIsLockedAgainstPriceMovement() public {
    vm.deal(address(salaryPool), 10 ether);

    payroll.setBudget(1000);

    vm.prank(employee);
    payroll.registerEmployee(
        "EMP001",
        "John Doe",
        "Ministry of Finance",
        1
    );

    // ETH was $2,000 when the $1,000 budget was created.
    // Therefore the budget represents 0.5 ETH.
    assertEq(salaryPool.reservedFunds(), 0.5 ether);

    // ETH price falls from $2,000 to $1,000.
    priceFeed.updateAnswer(1000e8);

    vm.prank(employee);
    payroll.claimSalary();

    // Level 1 salary is $100.
    // $100 / $1,000 = 10% of the locked 0.5 ETH budget.
    // Employee should therefore receive 0.05 ETH.
    assertEq(employee.balance, 0.05 ether);
}
}