// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IParent {
    function addShortPosition(address _shortTokenAddress, address _baseTokenAddress, uint256 _baseTokenAmount)
        external
        returns (bool);

    function getNeededCollateralAmount(address _shortTokenAddress, address _baseTokenAddress, uint256 _shortTokenAmount)
        external
        returns (bool);

    function retrieveChildContracts() external returns (address[] memory);
}
