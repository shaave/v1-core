// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/contracts/libraries/AddressArray.sol";

contract Test_AddressArray is Test {
    using AddressArray for address[];
    address[] private testArray;
    address[] private expectedArray;

    function test_removeAddress_addressFound() public {

        // Arrange
        address keepAddress1  = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;
        address keepAddress2  = 0x00cf72a0Afc5d6d3AB4eEf51bC2fbEDC504Ac1db;
        address removeAddress = 0x2dd6F066F5af0fc1C8e502d4aCff598a8bc777d4;

        testArray.push(keepAddress1);
        testArray.push(removeAddress);
        testArray.push(keepAddress2);

        expectedArray = [keepAddress1, keepAddress2];

        // Act
        testArray.removeAddress(removeAddress);

        // Assert
        assertEq(testArray, expectedArray);
    }

    function test_removeAddress_addressNotFound() public {

        // Arrange
        address keepAddress1  = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;
        address keepAddress2  = 0x00cf72a0Afc5d6d3AB4eEf51bC2fbEDC504Ac1db;
        address keepAddress3  = 0x527aF79b652F47Daa8f9D5E10AE7Ca273468981E;
        address removeAddress = 0x2dd6F066F5af0fc1C8e502d4aCff598a8bc777d4;

        testArray.push(keepAddress1);
        testArray.push(keepAddress2);
        testArray.push(keepAddress3);

        expectedArray = [keepAddress1, keepAddress2, keepAddress3];

        // Act
        testArray.removeAddress(removeAddress);

        // Assert
        assertEq(testArray, expectedArray);
    }

    function test_includes_addressIncluded() public {

        // Arrange
        bool    addressIncluded  = false; 
        address testAddress1     = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;
        address testAddress2     = 0x00cf72a0Afc5d6d3AB4eEf51bC2fbEDC504Ac1db;
        address targetAddress    = 0x2dd6F066F5af0fc1C8e502d4aCff598a8bc777d4;

        testArray.push(testAddress1);
        testArray.push(testAddress2);
        testArray.push(targetAddress);

        // Act
        addressIncluded = testArray.includes(targetAddress);

        // Assert
        assertEq(addressIncluded, true);
    }

    function test_includes_addressNotIncluded() public {

        // Arrange
        bool    addressIncluded  = false; 
        address testAddress1     = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;
        address testAddress2     = 0x00cf72a0Afc5d6d3AB4eEf51bC2fbEDC504Ac1db;
        address testAddress3     = 0x527aF79b652F47Daa8f9D5E10AE7Ca273468981E;
        address targetAddress    = 0x2dd6F066F5af0fc1C8e502d4aCff598a8bc777d4;

        testArray.push(testAddress1);
        testArray.push(testAddress2);
        testArray.push(testAddress3);

        // Act
        addressIncluded = testArray.includes(targetAddress);

        // Assert
        assertEq(addressIncluded, false);
    }
}