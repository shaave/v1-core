// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/contracts/libraries/Math.sol";

contract Test_Math is Test {
    using Math for uint;

    /*******************************************************************************
    **
    **  dividedBy tests
    **
    *******************************************************************************/

    function test_dividedBy() public {

        // Arrange
        uint numerator     = 13;
        uint denominator   = 3;
        uint precision     = 0;
        uint quotient;

        // Act
        quotient = numerator.dividedBy(denominator, precision);

        // Assert
        assertEq(quotient, 4);
    }

    function test_dividedBy_nonzeroPrecision() public {

        // Arrange
        uint numerator     = 13;
        uint denominator   = 3;
        uint precision     = 18;
        uint quotient;

        // Act
        quotient = numerator.dividedBy(denominator, precision);

        // Assert
        assertEq(quotient, 4333333333333333333);
    }
}