// contracts/ShortStop.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


interface IShaaveChild {

    function short(
        address _shortTokenAddress,
        uint _collateralTokenAmount,
        address _userAddress
    ) external;

    function reducePosition(
        address _shortTokenAddress,
        uint _percentageReduction,
        bool _withdrawCollateral
    ) external;

    function repayOutstandingDebt(
        address _shortTokenAddress,
        address _paymentToken,
        uint _paymentAmount,
        bool _withdrawCollateral
    ) external;

    function getOutstandingDebt(address _shortTokenAddress) external;

    function getOutstandingDebtBase(address _shortTokenAddress) external;

    function getAccountingData() external;
    
    function getAaveAccountData() external;

    function withdrawCollateral(uint _withdrawAmount) external;
}