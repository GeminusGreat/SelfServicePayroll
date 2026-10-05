// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SalaryPool} from "../src/SalaryPool.sol";

contract SalaryPoolTest is Test {
    SalaryPool public salaryPool;

    address public payroll;
    address public employee;
    address public anotherUser;

    uint256 public constant INITIAL_POOL_BALANCE = 10 ether;
    uint256 public constant RESERVED_AMOUNT = 5 ether;
    uint256 public constant SALARY_AMOUNT = 2 ether;

    receive() external payable {}

    function setUp() public {
        // Deploy SalaryPool.
        salaryPool = new SalaryPool();

        // Test addresses.
        payroll = makeAddr("payroll");
        employee = makeAddr("employee");
        anotherUser = makeAddr("anotherUser");

        // Fund the SalaryPool.
        vm.deal(
            address(salaryPool),
            INITIAL_POOL_BALANCE
        );

        // Configure the payroll contract.
        salaryPool.setPayrollContract(payroll);
    }


    //                       DEPLOYMENT
    

    function testOwnerIsDeployer() public{
        assertEq(
            salaryPool.owner(),
            address(this)
        );
    }

    function testPayrollContractIsSet() public {
        assertEq(
            salaryPool.payrollContract(),
            payroll
        );
    }

 
    //                         FUNDING
  

    function testPoolReceivesEther() public {
        uint256 amount = 1 ether;

        vm.deal(anotherUser, amount);

        vm.prank(anotherUser);

        (bool success,) =
            address(salaryPool).call{
                value: amount
            }("");

        assertTrue(success);

        assertEq(
            address(salaryPool).balance,
            INITIAL_POOL_BALANCE + amount
        );
    }

    function testFundFunction() public {
        uint256 amount = 2 ether;

        vm.deal(anotherUser, amount);

        vm.prank(anotherUser);

        salaryPool.fund{value: amount}();

        assertEq(
            address(salaryPool).balance,
            INITIAL_POOL_BALANCE + amount
        );
    }

    // =============================================================
    //                    PAYROLL AUTHORIZATION
    // =============================================================

    function testOnlyPayrollCanReserveFunds() public {
        vm.prank(anotherUser);

        vm.expectRevert(
            SalaryPool.NotPayroll.selector
        );

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );
    }

    function testOnlyPayrollCanReleaseFunds() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        vm.prank(anotherUser);

        vm.expectRevert(
            SalaryPool.NotPayroll.selector
        );

        salaryPool.releaseReservedFunds(
            RESERVED_AMOUNT
        );
    }

    function testOnlyPayrollCanPayEmployee() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        vm.prank(anotherUser);

        vm.expectRevert(
            SalaryPool.NotPayroll.selector
        );

        salaryPool.payEmployee(
            payable(employee),
            SALARY_AMOUNT
        );
    }

    // =============================================================
    //                       RESERVATIONS
    // =============================================================

    function testPayrollCanReserveFunds() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        assertEq(
            salaryPool.reservedFunds(),
            RESERVED_AMOUNT
        );
    }

    function testCannotReserveMoreThanPoolBalance() public {
        vm.prank(payroll);

        vm.expectRevert(
            SalaryPool.InsufficientPoolBalance.selector
        );

        salaryPool.reserveFunds(
            INITIAL_POOL_BALANCE + 1
        );
    }

    function testReservedFundsCannotBeWithdrawn() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        vm.expectRevert(
            SalaryPool.WithdrawalTooHigh.selector
        );

        salaryPool.ownerWithdraw(
            INITIAL_POOL_BALANCE
        );
    }

    // =============================================================
    //                    RELEASE RESERVED FUNDS
    // =============================================================

    function testPayrollCanReleaseReservedFunds() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        vm.prank(payroll);

        salaryPool.releaseReservedFunds(
            2 ether
        );

        assertEq(
            salaryPool.reservedFunds(),
            3 ether
        );
    }

    function testCannotReleaseMoreThanReserved() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        vm.prank(payroll);

        vm.expectRevert(
            SalaryPool.InsufficientPoolBalance.selector
        );

        salaryPool.releaseReservedFunds(
            RESERVED_AMOUNT + 1
        );
    }

    // =============================================================
    //                         PAYMENTS
    // =============================================================

    function testPayrollCanPayEmployee() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        uint256 employeeBalanceBefore =
            employee.balance;

        vm.prank(payroll);

        salaryPool.payEmployee(
            payable(employee),
            SALARY_AMOUNT
        );

        assertEq(
            employee.balance,
            employeeBalanceBefore + SALARY_AMOUNT
        );

        assertEq(
            salaryPool.reservedFunds(),
            RESERVED_AMOUNT - SALARY_AMOUNT
        );
    }

    function testCannotPayMoreThanReservedFunds() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        vm.prank(payroll);

        vm.expectRevert(
            SalaryPool.InsufficientPoolBalance.selector
        );

        salaryPool.payEmployee(
            payable(employee),
            RESERVED_AMOUNT + 1
        );
    }

    // =============================================================
    //                     OWNER WITHDRAWAL
    // =============================================================

   function testOwnerCanWithdrawAvailableFunds() public {
    vm.prank(payroll);

    salaryPool.reserveFunds(
        RESERVED_AMOUNT
    );

    vm.deal(
        address(this),
        1 ether
    );

    uint256 ownerBalanceBefore =
        address(this).balance;

    salaryPool.ownerWithdraw(
        1 ether
    );

    assertEq(
        address(this).balance,
        ownerBalanceBefore + 1 ether
    );
}

    function testNonOwnerCannotWithdraw() public {
        vm.prank(anotherUser);

        vm.expectRevert(
            SalaryPool.NotOwner.selector
        );

        salaryPool.ownerWithdraw(
            1 ether
        );
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function testPoolBalance() public {
        assertEq(
            salaryPool.poolBalance(),
            INITIAL_POOL_BALANCE
        );
    }

    function testAvailableFundsWithoutReservation() public {
        assertEq(
            salaryPool.availableFunds(),
            INITIAL_POOL_BALANCE
        );
    }

    function testAvailableFundsAfterReservation() public {
        vm.prank(payroll);

        salaryPool.reserveFunds(
            RESERVED_AMOUNT
        );

        assertEq(
            salaryPool.availableFunds(),
            INITIAL_POOL_BALANCE - RESERVED_AMOUNT
        );
    }
}