// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {PriceConverter} from "./libraries/PriceConverter.sol";
import {SalaryPool} from "./SalaryPool.sol";

// =============================================================
//                           ERRORS
// =============================================================

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
error BudgetAlreadySet();

// =============================================================
//                         CONTRACT
// =============================================================

/**
 * @title SelfServicePayRoll
 * @notice Government monthly self-service payroll system.
 *
 * @dev
 * This contract manages payroll rules and employee records.
 *
 * SalaryPool is responsible for custody of ETH.
 */
contract SelfServicePayRoll {
    using PriceConverter for uint256;

    // =============================================================
    //                         STRUCTS
    // =============================================================

    struct Employee {
        string name;
        string ministry;
        uint8 level;
        address wallet;
        bool isSuspended;
        uint8 deductionPercent;
        uint256 deductionPeriod;
        uint256 lastPaidPeriod;
        bool registered;
    }

    // =============================================================
    //                          STATE
    // =============================================================

    address public immutable OWNER;

    AggregatorV3Interface public immutable PRICEFEED;

    SalaryPool public immutable SALARYPOOL;

    /**
     * @notice USD salary for each government salary level.
     *         Values use 18 decimals.
     */
    mapping(uint8 level => uint256 salaryUsd)
        public salaryByLevel;

    mapping(string staffId => Employee employee)
        public employees;

    mapping(address employeeAddress => string staffId)
        public addressToStaffId;

    /**
     * @notice Current month's USD budget.
     */
    uint256 public budget;

    bool public budgetSet;

    /**
     * @notice Current payroll period.
     */
    uint256 public payrollPeriod;

    uint256 public employeeCount;

    uint256 public employeesPaid;

    // =============================================================
    //                           EVENTS
    // =============================================================

    event EmployeeRegistered(
        string indexed staffId,
        address indexed wallet,
        uint8 indexed level
    );

    event SalaryUpdated(
        uint8 level,
        uint256 newSalaryUsd
    );

    event BudgetUpdated(
        uint256 newBudgetUsd,
        uint256 reservedEth
    );

    event EmployeeSuspended(
        string indexed staffId
    );

    event EmployeeUnsuspended(
        string indexed staffId
    );

    event SalaryCut(
        string indexed staffId,
        uint8 percent
    );

    event PenaltyReset(
        string indexed staffId
    );

    event NewPayrollStarted(
        uint256 indexed payrollPeriod
    );

    event SalaryClaimed(
        string indexed staffId,
        address indexed wallet,
        uint256 indexed amountUsd,
        uint256 amountWei
    );

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }

        _;
    }

    modifier employeeExists(
        string memory staffId
    ) {
        if (!employees[staffId].registered) {
            revert EmployeeNotFound();
        }

        _;
    }

    modifier validLevel(
        uint8 level
    ) {
        if (level == 0 || level > 4) {
            revert InvalidLevel();
        }

        _;
    }

    modifier budgetIsSet() {
        if (!budgetSet) {
            revert BudgetNotSet();
        }

        _;
    }

    // =============================================================
    //                       CONSTRUCTOR
    // =============================================================

    constructor(
        address priceFeedAddress,
        address salaryPoolAddress
    ) {
        OWNER = msg.sender;

        PRICEFEED =
            AggregatorV3Interface(priceFeedAddress);

        SALARYPOOL =
            SalaryPool(payable(salaryPoolAddress));

        payrollPeriod = 1;

        salaryByLevel[1] = 100 * 1e18;
        salaryByLevel[2] = 170 * 1e18;
        salaryByLevel[3] = 320 * 1e18;
        salaryByLevel[4] = 650 * 1e18;
    }

    // =============================================================
    //                    EMPLOYEE REGISTRATION
    // =============================================================

    function registerEmployee(
        string memory staffId,
        string memory name,
        string memory ministry,
        uint8 level
    )
        public
        validLevel(level)
    {
        if (bytes(staffId).length == 0) {
            revert InvalidStaffId();
        }

        if (employees[staffId].registered) {
            revert EmployeeAlreadyRegistered();
        }

        if (
            bytes(addressToStaffId[msg.sender]).length != 0
        ) {
            revert WalletAlreadyRegistered();
        }

        Employee storage emp =
            employees[staffId];

        emp.name = name;
        emp.ministry = ministry;
        emp.level = level;
        emp.wallet = msg.sender;
        emp.isSuspended = false;
        emp.deductionPercent = 0;
        emp.deductionPeriod = 0;
        emp.lastPaidPeriod = 0;
        emp.registered = true;

        addressToStaffId[msg.sender] =
            staffId;

        employeeCount++;

        emit EmployeeRegistered(
            staffId,
            msg.sender,
            level
        );
    }

    // =============================================================
    //                         SALARIES
    // =============================================================

    function setSalary(
        uint8 level,
        uint256 newSalaryDollars
    )
        public
        onlyOwner
        validLevel(level)
    {
        uint256 newSalaryUsd =
            newSalaryDollars * 1e18;

        salaryByLevel[level] =
            newSalaryUsd;

        emit SalaryUpdated(
            level,
            newSalaryUsd
        );
    }

    // =============================================================
    //                          BUDGET
    // =============================================================

    /**
     * @notice Sets the USD budget and reserves its ETH equivalent.
     */
    function setBudget(uint256 newBudgetDollars) public onlyOwner {
    if (budgetSet) {
        revert BudgetAlreadySet();
    }

    uint256 newBudgetUsd = newBudgetDollars * 1e18;
    uint256 requiredEth = newBudgetUsd.usdToEth(PRICEFEED);

    budget = newBudgetUsd;
    budgetSet = true;

    SALARYPOOL.reserveFunds(requiredEth);

    emit BudgetUpdated(newBudgetUsd, requiredEth);
}

    // =============================================================
    //                     EMPLOYEE MANAGEMENT
    // =============================================================

    function suspendEmployee(
        string memory staffId
    )
        public
        onlyOwner
        employeeExists(staffId)
    {
        employees[staffId].isSuspended = true;

        emit EmployeeSuspended(staffId);
    }

    function unsuspendEmployee(
        string memory staffId
    )
        public
        onlyOwner
        employeeExists(staffId)
    {
        employees[staffId].isSuspended = false;

        emit EmployeeUnsuspended(staffId);
    }

    function cutSalary(
        string memory staffId,
        uint8 percent
    )
        public
        onlyOwner
        employeeExists(staffId)
    {
        if (percent > 100) {
            revert InvalidPercentage();
        }

        employees[staffId].deductionPercent =
            percent;

        employees[staffId].deductionPeriod =
            payrollPeriod;

        emit SalaryCut(
            staffId,
            percent
        );
    }

    function resetPenalty(
        string memory staffId
    )
        public
        onlyOwner
        employeeExists(staffId)
    {
        employees[staffId].deductionPercent = 0;
        employees[staffId].deductionPeriod = 0;

        emit PenaltyReset(staffId);
    }

    // =============================================================
    //                      PAYROLL PERIOD
    // =============================================================

    /**
     * @notice Starts the next payroll period.
     *
     * @dev Any unused ETH reservation from the previous payroll
     *      is released. Employees who did not claim their previous
     *      salary lose that claim.
     */
    function startNewPayroll()
        public
        onlyOwner
    {
        uint256 reserved =
            SALARYPOOL.reservedFunds();

        if (reserved > 0) {
            SALARYPOOL.releaseReservedFunds(
                reserved
            );
        }

        budget = 0;

        budgetSet = false;

        payrollPeriod++;

        employeesPaid = 0;

        emit NewPayrollStarted(
            payrollPeriod
        );
    }

    // =============================================================
    //                       SALARY CLAIM
    // =============================================================

    /**
     * @notice Employee claims their salary for the current month.
     */
    function claimSalary()
        public
        budgetIsSet
    {
        string memory staffId =
            addressToStaffId[msg.sender];

        if (bytes(staffId).length == 0) {
            revert EmployeeNotFound();
        }

        Employee storage emp =
            employees[staffId];

        if (emp.isSuspended) {
            revert EmployeeIsSuspended();
        }

        if (
            emp.lastPaidPeriod ==
            payrollPeriod
        ) {
            revert AlreadyPaid();
        }

        uint256 baseSalaryUsd =
            salaryByLevel[emp.level];

        uint256 deductionUsd = 0;

        if (
            emp.deductionPeriod ==
            payrollPeriod
        ) {
            deductionUsd =
                (
                    baseSalaryUsd *
                    emp.deductionPercent
                ) / 100;
        }

        uint256 finalUsd =
            baseSalaryUsd -
            deductionUsd;

        if (finalUsd == 0) {
            revert ZeroPayment();
        }

        if (finalUsd > budget) {
            revert BudgetNotFunded();
        }

        uint256 reservedEth = SALARYPOOL.reservedFunds();

if (reservedEth == 0) {
    revert BudgetNotFunded();
}

uint256 finalWei = (reservedEth * finalUsd) / budget;

if (finalWei == 0) {
    revert ZeroPayment();
}
        // Effects before interaction.
        emp.lastPaidPeriod =
            payrollPeriod;

        budget -= finalUsd;

        employeesPaid++;

        // SalaryPool performs the actual ETH transfer.
        SALARYPOOL.payEmployee(
            payable(msg.sender),
            finalWei
        );

        emit SalaryClaimed(
            staffId,
            msg.sender,
            finalUsd,
            finalWei
        );
    }

    // =============================================================
    //                       VIEW HELPERS
    // =============================================================

    function requiredEthForBudget()
        public
        view
        returns (uint256)
    {
        return budget.usdToEth(
            PRICEFEED
        );
    }

    function getLatestEthPriceUsd()
        public
        view
        returns (uint256)
    {
        return PriceConverter.getPrice(
            PRICEFEED
        );
    }

    function getContractBalanceInUsd()
    public
    view
    returns (uint256)
{
    return
        address(SALARYPOOL)
            .balance
            .ethToUsd(PRICEFEED);
}

    function myStaffId()
        public
        view
        returns (string memory)
    {
        return addressToStaffId[msg.sender];
    }
}
