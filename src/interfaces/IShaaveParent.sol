// contracts/ShortStop.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


interface IShaaveParent {

    function addShortPosition(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _baseTokenAmount
    ) external returns (bool);

    function getNeededCollateralAmount(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _shortTokenAmount
    ) external returns (bool);


    function retrieveChildContracts() external returns (address[] memory);
}