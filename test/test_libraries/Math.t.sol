// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/libraries/Math.sol";

contract MathTest is Test {
    using Math for uint256;

    function test_dividedBy() public {
        // Setup
        uint256 numerator = 13;
        uint256 denominator = 3;
        uint256 precision = 0;
        uint256 quotient;

        // Act
        quotient = numerator.dividedBy(denominator, precision);

        // Assertions
        assertEq(quotient, 4);
    }

    function test_dividedBy_nonzeroPrecision() public {
        // Setup
        uint256 numerator = 13;
        uint256 denominator = 3;
        uint256 precision = 18;
        uint256 quotient;

        // Act
        quotient = numerator.dividedBy(denominator, precision);

        // Assertions
        assertEq(quotient, 4333333333333333333);
    }
}
