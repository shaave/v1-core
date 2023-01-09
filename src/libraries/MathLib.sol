// contracts/libraries/MathLib.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title MathLib library
 * @author shAave
 * @dev Implements logic for math calculations
 * @notice dividedBy() truncates the result. It does NOT round up the result.
 */
library MathLib {
    function dividedBy(uint256 numerator, uint256 denominator, uint256 precision) internal pure returns (uint256) {
        return numerator * (uint256(10) ** uint256(precision)) / denominator;
    }
}
