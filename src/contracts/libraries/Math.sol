// contracts/libraries/Math.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

/**
 * @title Math library
 * @author shAave
 * @dev Implements logic for math calculations
 * @notice dividedBy() truncates the result. It does NOT round up the result. 
*/
library Math {

    function dividedBy(uint numerator, uint denominator, uint precision) internal pure returns(uint) {
        return numerator*(uint(10)**uint(precision))/denominator;
    }
    
}