pragma solidity ^0.4.11;

/** TODO

Employee Struct for allocation/allowedTokens is all messed up
Should I use sub-structs somehow?

Can I hash the address to get employeeId instead of using sequential numbering?
Array vs mapping for employees

Contract balance is in ETH but payouts in USD??

Read up on Memory vs Storage pointers

**/

contract Payroll {
    
    struct Employee {
        // Initial Setup
        address accountAddress;
        uint256 SalaryUSD;
        address[] allowedTokens;
        uint lastWithdrawalTime;
        bool isValid;           // default false; used to remove employees

        // Allocation and Payment 
        uint lastAllocationTime;
        address[] tokens;
        mapping (address => uint256) distribution;
    }
    
    Employee[] employees;
    uint256 numEmployees;
    mapping (address => uint) employeeAddressToId;

    /* CONSTRUCTOR */
    function Payroll() 
    {
        numEmployees = 0;
    }
    


    /* OWNER ONLY */

    function addEmployee(address accountAddress, address[] allowedTokens, uint256 initialYearlyUSDSalary) 
    external returns (uint256) 
    {
        // Employee IDs increment sequentially up to 2**256-1
        // Check first for overflow
        require(employees.length < 2**256-1);
        uint256 employeeId = employees.length;
        
        // Create employee, add to payroll, and update address lookup table
        Employee memory employee = Employee(accountAddress, initialYearlyUSDSalary, allowedTokens, now, true);
        employeeAddressToId[accountAddress] = employeeId;
        employees.push(employee);

        numEmployees++;
        return employeeId;
    }

    // Helper function to get the employee struct from an ID
    function _getEmployeeStruct(uint256 employeeId) 
    internal constant returns (Employee storage) 
    {
        Employee storage employee = employees[employeeId];
        require(employee.isValid);
        return employee;
    }
    
    function removeEmployee(uint256 employeeId) 
    external 
    {
        Employee storage employee = _getEmployeeStruct(employeeId);
        employee.isValid = false;
        numEmployees--;
    }

    function setEmployeeSalary(uint256 employeeId, uint256 yearlyUSDSalary) 
    external
    {
        Employee storage employee = _getEmployeeStruct(employeeId);
        employee.SalaryUSD = yearlyUSDSalary;
    }

    // function addFunds() payable;
    // function scapeHatch();
    // function addTokenFunds()? // Use approveAndCall or ERC223 tokenFallback

    function getEmployeeCount() 
    external constant returns (uint256) 
    {
        return numEmployees;
    }
  
    function getEmployee(uint256 employeeId) 
    external constant returns (address accountAddress, uint256 SalaryUSD) 
    {
        Employee storage employee = _getEmployeeStruct(employeeId);
        accountAddress = employee.accountAddress;
        SalaryUSD = employee.SalaryUSD;
    }

    function calculatePayrollBurnrate() 
    public constant returns (uint256)
    {
        uint256 totalSalaries = 0;
        for (uint i=0; i<employees.length; i++) {
            Employee storage e = employees[i];
            if (e.isValid) {
                totalSalaries += e.SalaryUSD;
            }
        return totalSalaries/12;
        }
    }

    function calculatePayrollRunway()
    external constant returns (uint256 daysLeft)
    // Currently assumes a month is 30 days
    {
        uint256 monthlyBurnRate = calculatePayrollBurnrate();
        uint256 dailyBurnRate = monthlyBurnRate/30;
        daysLeft = this.balance/dailyBurnRate;
    }



    /* EMPLOYEE ONLY */
    
    // Helper function to get the employee struct from an address
    function _getEmployeeStruct(address accountAddress) 
    internal constant returns (Employee storage) 
    {
        uint256 employeeId = employeeAddressToId[accountAddress];
        Employee storage e = _getEmployeeStruct(employeeId);
        // In case the employee doesn't exist, we'll get employee 0
        // So let's make sure we have the right one
        require(accountAddress == e.accountAddress);
        return e;
    }


    function determineAllocation(address[] _tokens, uint256[] _distribution)
    external
    {
        // Get the employee
        Employee storage e = _getEmployeeStruct(msg.sender);
        
        // Make sure they only re-allocate once in 6 months
        require(now - e.lastAllocationTime >= 180 days);
        require(_tokens.length == _distribution.length);
        
        // Clear any previous allocation
        delete e.tokens;  

        uint256 totalDistribution = 0;
        for (uint i=0; i<_tokens.length; i++) {
            address _t = _tokens[i];
            uint256 amount = _distribution[i];
            
            // Make sure it is allowed
            require(e.allowedTokens[_t]);
            
            e.tokens.push(_t);
            e.distribution[_t] = amount;
            totalDistribution += amount;            
        }
        
        // Finally, check to make sure the distribution matches salary
        require (e.SalaryUSD == totalDistribution);
        
        e.lastAllocationTime = now;

    }

    function payday()
    external payable {
        // Get the employee
        Employee storage e = _getEmployeeStruct(msg.sender);

        // Payouts only once a month
        require(now - e.lastWithdrawalTime >= 30 days);
        
        // Payout to each allocated token address
        for (uint i=0; i<=e.tokens.length; i++) {
            address _t = e.tokens[i];
            uint256 amount = e.distribution[_t];
            bool success = _t.send(amount);
            require(success);
        }
    }

//   /* ORACLE ONLY */
//   function setExchangeRate(address token, uint256 usdExchangeRate); // uses decimals from token
}
