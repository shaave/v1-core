// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


contract MockAavePool {

    function supply() public pure returns (bool) {
        return true;
    }

    function borrow() public pure returns (bool) {
        return true;
    }
}