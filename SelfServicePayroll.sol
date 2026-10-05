// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts@0.8.0/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";

//Custom Errors
error NotOwner();
error EmployeeNotFound();
error EmployeeAlreadyRegistered();
error WalletAlreadyRegistered();
error InvalidStaffId();
error EmployeeIsSuspended();
error AlreadyPaid();
error BudgetNotFunded();
error BudgetNotSet();
error InvalidPercentage();
error InvalidLevel();
error ZeroPayment();
error WithdrawalTooHigh();
error TransferFailed();

/**
 * @title SelfServicePayrollUSD
 * @notice Monthly payroll. Salaries and budget are in USD via a live Chainlink ETH/USD feed.
 *         Employees pull their own pay with claimSalary(), once per payroll period (month).
 *         The owner calls startNewPayroll() at the start of each month.
 */
contract SelfServicePayRoll {
    using PriceConverter for uint256;

    //Structure For Employee
    struct Employee {
        string name;
        string ministry;
        uint8 level;
        address wallet;
        bool isSuspended;
        uint8 deductionPercent;
        // The payroll period (month) in which the salary cut was made
        uint256 deductionPeriod;
        // The payroll period (month) in which the employee last got paid
        uint256 lastPaidPeriod;
        bool registered;
    }

    address public immutable owner;
    AggregatorV3Interface public immutable priceFeed;

    // 18-decimal USD amounts throughout: $100 is stored as 100e18
    mapping(uint8 Level => uint256 Salary) public salaryByLevel;

    mapping(string StaffID => Employee) public employees;
    mapping(address EmployeeAdress => string StaffID) public addressToStaffId;

    // USD, 18 decimals - the money left to pay out this month. It shrinks each time someone is paid.
    uint256 public budget;

    // becomes true when the owner calls setBudget() - claims are blocked until then
    bool public budgetSet;

    // The current payroll period (month). It starts at 1 and goes up by 1 each new payroll.
    uint256 public payrollPeriod;

    // How many employees have registered, and how many have been paid this month
    uint256 public employeeCount;
    uint256 public employeesPaid;

    // Events
    event EmployeeRegistered(
        string indexed staffId,
        address indexed wallet,
        uint8 indexed level
    );
    event SalaryUpdated(uint8 level, uint256 newSalaryUsd);
    event BudgetUpdated(uint256 newBudgetUsd);
    event Funded(address from, uint256 amountWei);
    event EmployeeSuspended(string indexed staffId);
    event EmployeeUnsuspended(string indexed staffId);
    event SalaryCut(string staffId, uint8 percent);
    event PenaltyReset(string staffId);
    event NewPayrollStarted(uint256 indexed payrollPeriod);
    event SalaryClaimed(
        string indexed staffId,
        address indexed wallet,
        uint256 indexed amountUsd,
        uint256 amountWei
    );
    event OwnerWithdrew(uint256 amountWei);

    // Modifiers

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier employeeExists(string memory staffId) {
        if (!employees[staffId].registered) revert EmployeeNotFound();
        _;
    }

    modifier validLevel(uint8 level) {
        if (level == 0 || level > 4) revert InvalidLevel();
        _;
    }

    // Blocks any claim until the owner has called setBudget() for this month.
    modifier budgetIsSet() {
        if (!budgetSet) revert BudgetNotSet();
        _;
    }

    // Constructor

    // priceFeedAddress Sepolia testnet ETH/USD example: 0x694AA1769357215DE4FAC081bf1f309aDC325306
    constructor(address priceFeedAddress) {
        owner = msg.sender;
        priceFeed = AggregatorV3Interface(priceFeedAddress);

        // The first month
        payrollPeriod = 1;

        salaryByLevel[1] = 100 * 1e18;
        salaryByLevel[2] = 170 * 1e18;
        salaryByLevel[3] = 320 * 1e18;
        salaryByLevel[4] = 650 * 1e18;
    }

    // Employee self-registration (for testing only)
    // The wallet that calls this function becomes the employee's wallet.

    function registerEmployee(
        string memory staffId,
        string memory name,
        string memory ministry,
        uint8 level
    ) public validLevel(level) {
        if (bytes(staffId).length == 0) revert InvalidStaffId();
        if (employees[staffId].registered) revert EmployeeAlreadyRegistered();
        if (bytes(addressToStaffId[msg.sender]).length != 0)
            revert WalletAlreadyRegistered();

        Employee storage emp = employees[staffId];
        emp.name = name;
        emp.ministry = ministry;
        emp.level = level;
        emp.wallet = msg.sender;
        emp.isSuspended = false;
        emp.deductionPercent = 0;
        emp.deductionPeriod = 0;
        emp.lastPaidPeriod = 0;
        emp.registered = true;

        addressToStaffId[msg.sender] = staffId;
        employeeCount = employeeCount + 1;

        emit EmployeeRegistered(staffId, msg.sender, level);
    }

    // function to set Salary if theres a salary increase for levels...
    // Do this BEFORE setBudget() each month, so nobody's pay changes while they are claiming.
    function setSalary(
        uint8 level,
        uint256 newSalaryDollars
    ) public onlyOwner validLevel(level) {
        uint256 newSalaryUsd = newSalaryDollars * 1e18;
        salaryByLevel[level] = newSalaryUsd;
        emit SalaryUpdated(level, newSalaryUsd);
    }

    // function to set Budget for the month
    function setBudget(uint256 newBudgetDollars) public onlyOwner {
        uint256 newBudgetUsd = newBudgetDollars * 1e18;
        budget = newBudgetUsd;
        budgetSet = true;
        emit BudgetUpdated(newBudgetUsd);
    }

    // Funding
    // receive() must be external, the compiler does not allow it to be public

    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    // The owner cannot take out the ETH that is still needed to pay the budget

    function ownerWithdraw(uint256 amountWei) public onlyOwner {
        uint256 neededWei = budget.usdToEth(priceFeed);
        if (address(this).balance < amountWei + neededWei)
            revert WithdrawalTooHigh();

        (bool success, ) = payable(owner).call{value: amountWei}("");
        if (!success) revert TransferFailed();
        emit OwnerWithdrew(amountWei);
    }

    // Owner: suspend / cut salary for defaulters

    function suspendEmployee(
        string memory staffId
    ) public onlyOwner employeeExists(staffId) {
        employees[staffId].isSuspended = true;
        emit EmployeeSuspended(staffId);
    }

    function unsuspendEmployee(
        string memory staffId
    ) public onlyOwner employeeExists(staffId) {
        employees[staffId].isSuspended = false;
        emit EmployeeUnsuspended(staffId);
    }

    // The cut only counts for the month it was made in.
    function cutSalary(
        string memory staffId,
        uint8 percent
    ) public onlyOwner employeeExists(staffId) {
        if (percent > 100) revert InvalidPercentage();
        employees[staffId].deductionPercent = percent;
        employees[staffId].deductionPeriod = payrollPeriod;
        emit SalaryCut(staffId, percent);
    }

    // Owner: remove one employee's penalty before they are paid this month.
    // You do NOT need this at the start of a new month, because old cuts stop
    // counting by themselves when a new payroll starts.
    function resetPenalty(
        string memory staffId
    ) public onlyOwner employeeExists(staffId) {
        employees[staffId].deductionPercent = 0;
        employees[staffId].deductionPeriod = 0;
        emit PenaltyReset(staffId);
    }

    // Owner: start a new month.
    // - the old budget is cleared, so you must call setBudget() again
    // - the month number goes up, so every employee can be paid again
    // - every old salary cut stops counting
    // Employees who did not claim last month lose that month's pay,
    // so call this only after everyone has been paid.
    // (employeeCount - employeesPaid tells you how many are still unpaid)
    function startNewPayroll() public onlyOwner {
        budget = 0;
        budgetSet = false;
        payrollPeriod = payrollPeriod + 1;
        employeesPaid = 0;

        emit NewPayrollStarted(payrollPeriod);
    }

    // Employee: self-service payment, once per month

    /**
     * The only way ETH leaves this contract for an employee. Pays exactly their
     * level's USD salary (minus any deduction made this month), converted to ETH
     * at the current Chainlink price.
     *
     * An employee can only claim once per payroll period. lastPaidPeriod is set
     * BEFORE the transfer goes out, so there is no way to claim twice in a month,
     * even via a reentrancy attempt during the transfer itself.
     *
     * Requires setBudget() to have been called this month. The budget is the money
     * left to pay out: each time an employee is paid, their salary is subtracted from it.
     */
    function claimSalary() public budgetIsSet {
        string memory staffId = addressToStaffId[msg.sender];
        if (bytes(staffId).length == 0) revert EmployeeNotFound();

        Employee storage emp = employees[staffId];
        if (emp.isSuspended) revert EmployeeIsSuspended();
        if (emp.lastPaidPeriod == payrollPeriod) revert AlreadyPaid();

        uint256 baseSalaryUsd = salaryByLevel[emp.level];

        // A salary cut only counts if it was made in the current month
        uint256 deductionUsd = 0;
        if (emp.deductionPeriod == payrollPeriod) {
            deductionUsd = (baseSalaryUsd * emp.deductionPercent) / 100;
        }

        uint256 finalUsd = baseSalaryUsd - deductionUsd;

        // a 100% cut leaves nothing to pay
        if (finalUsd == 0) revert ZeroPayment();

        // the budget must still have enough left for this salary
        if (finalUsd > budget) revert BudgetNotFunded();

        uint256 finalWei = finalUsd.usdToEth(priceFeed);

        // the contract must hold enough ETH to pay it
        if (address(this).balance < finalWei) revert BudgetNotFunded();

        // effects before interaction - locks in "paid" before sending
        emp.lastPaidPeriod = payrollPeriod;
        budget = budget - finalUsd;
        employeesPaid = employeesPaid + 1;

        (bool success, ) = (msg.sender).call{value: finalWei}("");
        if (!success) revert TransferFailed();

        emit SalaryClaimed(staffId, msg.sender, finalUsd, finalWei);
    }

    // View helpers

    function requiredEthForBudget() public view returns (uint256) {
        return budget.usdToEth(priceFeed);
    }

    function getLatestEthPriceUsd() public view returns (uint256) {
        return PriceConverter.getPrice(priceFeed);
    }

    function getContractBalanceInUsd() public view returns (uint256) {
        return address(this).balance.ethToUsd(priceFeed);
    }

    function myStaffId() public view returns (string memory) {
        return addressToStaffId[msg.sender];
    }
}
