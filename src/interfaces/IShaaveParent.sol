// contracts/ShortStop.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


interface IShaaveParent {

    function addShortPosition(
        address _shortTokenAddress,
        uint _collateralTokenAmount
    ) external;

    function getNeededCollateralAmount(
        address _collateralTokenAddress,
        address _shortTokenAddress,
        uint _shortTokenAmount
    ) external;

    function returnUserContractByAddress(address _userAddress) external;

    function retrieveChildContracts() external;
}