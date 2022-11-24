// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


interface IShaaveChild {

    function short(
        address _shortTokenAddress,
        uint _baseTokenAmount,
        address _userAddress
    ) external returns (bool);

    function reducePosition(
        address _shortTokenAddress,
        uint _percentageReduction,
        bool _withdrawCollateral
    ) external returns (bool);

    function payOutstandingDebt(address _shortTokenAddress, address _paymentToken, uint _paymentAmount, bool _withdrawCollateral) external returns (bool);

    function getOutstandingDebt(address _shortTokenAddress) external returns (uint);

    function getOutstandingDebtBase(address _shortTokenAddress) external returns (uint);

    function getAccountingData() external;
    
    function getAaveAccountData() external returns (uint, uint, uint, uint, uint, uint, uint);

    function withdrawCollateral(uint _withdrawAmount) external;
}