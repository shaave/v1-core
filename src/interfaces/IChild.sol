// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IChild {
    function short(address _shortTokenAddress, uint256 _baseTokenAmount, address _userAddress)
        external
        returns (bool);

    function reducePosition(address _shortTokenAddress, uint256 _percentageReduction, bool _withdrawCollateral)
        external
        returns (bool);

    function payOutstandingDebt(
        address _shortTokenAddress,
        address _paymentToken,
        uint256 _paymentAmount,
        bool _withdrawCollateral
    ) external returns (bool);

    function getOutstandingDebt(address _shortTokenAddress) external returns (uint256);

    function getOutstandingDebtBase(address _shortTokenAddress) external returns (uint256);

    function getAccountingData() external;

    function getAaveAccountData() external returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);

    function withdrawCollateral(uint256 _withdrawAmount) external;

    function baseToken() external returns (address);
}
