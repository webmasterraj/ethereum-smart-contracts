pragma solidity ^0.4.15;


contract Payroll {
    
    struct Employee {
        // Core info
        address accountAddress;
        uint256 salaryUSD;
        uint lastWithdrawalTime;
        bool isActive;           // default false; used to remove employees while maintaining historical record

        // Payment allocation
        address[] allowedTokens;
        address[] allocatedTokens;
        uint256 lastAllocationTime;
        mapping (address => uint256) allocatedDistribution;
    }
    
    address private owner;
    address private oracle;
    Employee[] private employees;
    uint256 private numEmployees;
    mapping (address => uint256) private employeeAddressToId;
    
    address private USD_TOKEN;
    bool private escapeMode = false;


    /* MODIFIERS */

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }


    modifier onlyOracle {
        require(msg.sender == oracle);
        _;
    }
    
    
    modifier normalModeOnly {
        require(!escapeMode);
        _;
    }

    /* CONSTRUCTOR */

    function Payroll(address _oracle, address _usd_token) {
        numEmployees = 0;
        owner = msg.sender;
        oracle = _oracle;
        USD_TOKEN = _usd_token;
    }
    

    // Set the oracle address
    // @dev Only the owner can call this function
    // @param _oracle: address of the new oracle
    // @return nothing
    function setOracle(address _oracle)
    public onlyOwner normalModeOnly {
    oracle = _oracle;
    }


    // Add an employee
    // @dev Only the owner can call this function
    // @dev New employees are initialized with all of their salary allocated in USD 
    // @param accountAddress: address of the new employee
    // @param allowedTokens: array of tokens the employee is allowed to withdraw salary in
    // @param initialYearlyUSDSalary: employee's initial salary
    // @return employeeId: uint256 ID (array index) of the new employee
    function addEmployee(address _accountAddress, address[] _allowedTokens, uint256 _initialYearlyUSDSalary) 
    external onlyOwner normalModeOnly
    returns (uint256 employeeId) {
        // Employee IDs increment sequentially up to 2**256-1
        // Check for overflow
        require(employees.length <= 2**256-1);
        employeeId = employees.length;
        
        // Create employee
        Employee storage e; 
        e.accountAddress = _accountAddress; 
        e.salaryUSD = _initialYearlyUSDSalary;
        e.lastWithdrawalTime = now;
        e.isActive = true;
        e.allowedTokens = _allowedTokens;
        e.allocatedTokens = [USD_TOKEN];                                // Only allocate USD initially
        e.allocatedDistribution[USD_TOKEN] = _initialYearlyUSDSalary;    
        e.lastAllocationTime = 0;                                       // Employee can re-allocate immediately 

        // Add to payroll and to address lookup table
        employeeAddressToId[_accountAddress] = employeeId;
        employees.push(e);
        numEmployees++;
    }


    // Helper function to get the employee struct from an employee ID
    // @dev INTERNAL USE ONLY
    // @dev Only the owner can call this function
    // @param employeeId: ID of the employee
    // @return employee: instance of Employee struct
    function _getEmployee(uint256 employeeId) 
    internal constant onlyOwner normalModeOnly
    returns (Employee storage employee) {
        employee = employees[employeeId];
        require(employee.isActive);
    }
    

    // Get information about an employee
    // @dev Only the owner can call this function
    // @param employeeId: sequential ID assigned at create time
    // @param accountAddress: employee's account address 
    // @param salaryUSD: employee's current salary
    // @param lastWithdrawalTime: unix timestamp of employee's last withdrawal
    // @param isActive: bool whether they're still a current employee
    // @param [] allowedTokens: array of their allowed tokens
    // @param [] allocatedTokens: array of their allocated tokens
    // @param [] allocatedDistribution: array of distribution to allocated tokens, in USD salary terms
    // @param lastAllocationTime: unix timestamp of last time employee set allocation
    // TODO: returning dynamic-sized arrays can get expensive
    //       allow caller to get chunks of arrays instead 
    function getEmployee(uint256 employeeId) 
    external constant onlyOwner
    returns (address accountAddress, 
             uint256 salaryUSD,
             uint256 lastWithdrawalTime,
             bool isActive,
             address[] allowedTokens,
             address[] allocatedTokens,
             uint256[] allocatedDistribution,
             uint256 lastAllocationTime) {
        Employee storage e = _getEmployee(employeeId);
        accountAddress = e.accountAddress;
        salaryUSD = e.salaryUSD;
        lastWithdrawalTime = e.lastWithdrawalTime;
        isActive = e.isActive;
        allowedTokens = e.allowedTokens;
        allocatedTokens = e.allocatedTokens;
        
        // Create allocatedDistribution array by looking up amounts in mapping
        for (uint i = 0; i < allocatedTokens.length; i++) {
            address token = allocatedTokens[i];
            uint256 amount = e.allocatedDistribution[token];
            allocatedDistribution[i] = amount;
        }
        
        lastAllocationTime = e.lastAllocationTime;
    }


    function removeEmployee(uint256 employeeId) 
    external onlyOwner {
        Employee storage employee = _getEmployee(employeeId);
        employee.isActive = false;
        numEmployees--;
    }


    function setEmployeeSalary(uint256 employeeId, uint256 yearlyUSDSalary) 
    external onlyOwner {
        Employee storage employee = _getEmployee(employeeId);
        employee.salaryUSD = yearlyUSDSalary;
    }


    function addFunds() 
    payable external 
    returns (uint) {
        return this.balance;
    }


    function scapeHatch() 
    external onlyOwner {
        escapeMode = true;
    }


    function backToNormal() 
    external onlyOwner {
        escapeMode = false;
    }


    // function addTokenFunds()? // Use approveAndCall or ERC223 tokenFallback

    function getEmployeeCount() 
    external constant onlyOwner
    returns (uint256) {
        return numEmployees; 
    }
  

    function calculatePayrollBurnrate() 
    public constant onlyOwner
    returns (uint256 monthlyBurnRate)
    {
        uint256 totalSalaries = 0;
        for (uint i=0; i<employees.length; i++) {
            Employee storage e = employees[i];
            if (e.isActive) {
                totalSalaries += e.salaryUSD;
            }
        monthlyBurnRate = totalSalaries/12;
        }
    }


    function calculatePayrollRunway()
    external constant onlyOwner 
    returns (uint256 daysLeft) {
        // Currently assumes a month is 30 days
        uint256 monthlyBurnRate = calculatePayrollBurnrate();
        uint256 dailyBurnRate = monthlyBurnRate/30;
        daysLeft = this.balance/dailyBurnRate;
    }



    /* EMPLOYEE ONLY */
    
    // Helper function to get the employee struct from an address
    // Also verifies that only the employee can access their own account
    function _getAndValidateEmployee(address accountAddress) 
    internal constant 
    returns (Employee storage e) {
        uint256 employeeId = employeeAddressToId[accountAddress];
        e = _getEmployee(employeeId);
        // In case the employee doesn't exist, we'll get employee 0
        // So let's make sure we have the right one
        require(accountAddress == e.accountAddress);
    }


    // Helper function to check if a token is in an employee's allowed tokens
    // This is O(N) but only runs once every 6 months
    function _checkAllowedToken(address[] allowedTokens, address token)
    internal constant 
    returns (bool) {
        for (uint i = 0; i < allowedTokens.length; i++) {
            if (token == allowedTokens[i]) {
                return true;
            }            
        }
        return false;
    }

    function determineAllocation(address[] tokens, uint256[] distribution)
    external 
    returns (bool success) {
        // Get the employee
        Employee storage e = _getAndValidateEmployee(msg.sender);
        
        // Make sure they only re-allocate once in 6 months
        require(now - e.lastAllocationTime >= 180 days);
        require(tokens.length == distribution.length);
        
        // Create new distribution
        address[] allocatedTokens;
        uint256 totalDistribution = 0;
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = distribution[i];
            
            // Make sure it is allowed
            require(_checkAllowedToken(e.allowedTokens, token));
            
            allocatedTokens.push(token);
            e.allocatedDistribution[token] = amount;
            totalDistribution += amount;            
        }
        e.allocatedTokens = allocatedTokens;
        
        // Finally, check to make sure the distribution matches salary
        require (e.salaryUSD == totalDistribution);
        
        e.lastAllocationTime = now;
        success = true;

    }

    function payday()
    external {
        // Get the employee
        Employee storage e = _getAndValidateEmployee(msg.sender);

        // Payouts only once a month
        require(now - e.lastWithdrawalTime >= 30 days);
        
        // Payout to each allocated token address
        for (uint i = 0; i < e.allocatedTokens.length; i++) {
            address tokenAddress = e.allocatedTokens[i];
            uint256 amount = e.allocatedDistribution[tokenAddress];
            tokenAddress.transfer(amount);
        }
    }

//   /* ORACLE ONLY */
//   function setExchangeRate(address token, uint256 usdExchangeRate); // uses decimals from token
}

