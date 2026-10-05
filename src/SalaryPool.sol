// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title SalaryPool
 * @notice Custodies ETH used by the government payroll system.
 *
 * SelfServicePayRoll is responsible for:
 * - employees
 * - salaries
 * - deductions
 * - payroll periods
 * - deciding who gets paid
 *
 * SalaryPool is responsible for:
 * - holding ETH
 * - reserving payroll funds
 * - paying employees
 * - protecting reserved funds
 * - owner withdrawals of unreserved funds
 */
contract SalaryPool {
    // =============================================================
    //                           ERRORS
    // =============================================================

    error NotOwner();
    error NotPayroll();
    error InvalidPayrollAddress();
    error InsufficientPoolBalance();
    error WithdrawalTooHigh();
    error TransferFailed();

    // =============================================================
    //                           EVENTS
    // =============================================================

    event Funded(address indexed from, uint256 amount);

    event PayrollContractUpdated(
        address indexed oldPayroll,
        address indexed newPayroll
    );

    event FundsReserved(uint256 amount);

    event FundsReleased(uint256 amount);

    event SalaryPaid(
        address indexed employee,
        uint256 amount
    );

    event OwnerWithdrawn(
        address indexed owner,
        uint256 amount
    );

    // =============================================================
    //                           STATE
    // =============================================================

    address public immutable owner;

    /**
     * @notice Only this contract may request employee payments.
     */
    address public payrollContract;

    /**
     * @notice ETH currently reserved for payroll.
     *
     * Reserved ETH cannot be withdrawn by the owner.
     */
    uint256 public reservedFunds;

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyPayroll() {
        if (msg.sender != payrollContract) revert NotPayroll();
        _;
    }

    // =============================================================
    //                       CONSTRUCTOR
    // =============================================================

    constructor() {
        owner = msg.sender;
    }

    // =============================================================
    //                          FUNDING
    // =============================================================

    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    function fund() external payable {
        emit Funded(msg.sender, msg.value);
    }

    // =============================================================
    //                    PAYROLL CONFIGURATION
    // =============================================================

    /**
     * @notice Sets the payroll contract authorized to make payments.
     */
    function setPayrollContract(
        address newPayrollContract
    ) external onlyOwner {
        if (newPayrollContract == address(0)) {
            revert InvalidPayrollAddress();
        }

        address oldPayroll = payrollContract;

        payrollContract = newPayrollContract;

        emit PayrollContractUpdated(
            oldPayroll,
            newPayrollContract
        );
    }

    /**
     * @notice Reserves ETH for the current payroll budget.
     *
     * @dev The payroll contract calculates the ETH equivalent
     *      of its USD budget and calls this function.
     */
    function reserveFunds(
        uint256 amount
    ) external onlyPayroll {
        if (address(this).balance < amount) {
            revert InsufficientPoolBalance();
        }

        reservedFunds = amount;

        emit FundsReserved(amount);
    }

    /**
     * @notice Releases reserved funds.
     *
     * @dev Used when a new payroll starts and the previous
     *      payroll's unused budget expires.
     */
    function releaseReservedFunds(
        uint256 amount
    ) external onlyPayroll {
        if (amount > reservedFunds) {
            revert InsufficientPoolBalance();
        }

        reservedFunds -= amount;

        emit FundsReleased(amount);
    }

    // =============================================================
    //                          PAYMENTS
    // =============================================================

    /**
     * @notice Pays an employee from the pool.
     *
     * @dev Only SelfServicePayRoll can call this function.
     */
    function payEmployee(
        address payable employee,
        uint256 amount
    ) external onlyPayroll {
        if (amount > reservedFunds) {
            revert InsufficientPoolBalance();
        }

        if (address(this).balance < amount) {
            revert InsufficientPoolBalance();
        }

        // Effects before interaction.
        reservedFunds -= amount;

        (bool success, ) = employee.call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit SalaryPaid(employee, amount);
    }

    // =============================================================
    //                       OWNER WITHDRAWAL
    // =============================================================

    /**
     * @notice Withdraws only ETH that is not reserved for payroll.
     */
    function ownerWithdraw(
        uint256 amount
    ) external onlyOwner {
        uint256 availableBalance =
            address(this).balance - reservedFunds;

        if (amount > availableBalance) {
            revert WithdrawalTooHigh();
        }

        (bool success, ) =
            payable(owner).call{value: amount}("");

        if (!success) {
            revert TransferFailed();
        }

        emit OwnerWithdrawn(owner, amount);
    }

    // =============================================================
    //                         VIEW HELPERS
    // =============================================================

    function availableFunds()
        external
        view
        returns (uint256)
    {
        return address(this).balance - reservedFunds;
    }

    function poolBalance()
        external
        view
        returns (uint256)
    {
        return address(this).balance;
    }
}
