// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Local Imports
import "../src/contracts/ShaaveParent.sol";
import "../src/interfaces/IShaaveChild.sol";
import "../src/interfaces/IwERC20.sol";

import "./common/constants.t.sol";

// External Package Imports
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract ShaaveParentHelper is Test {
    using ShaavePricing for address;
    using Math for uint;

    // Constants              
    uint constant public LTV_BUFFER = 10;

    function getShaaveLTV(address baseToken) internal view returns (int) {
        uint bitMap = IPool(AAVE_POOL).getReserveData(baseToken).configuration.data;
        uint lastNbits = 16;               // bit 0-15: LTV
        uint mask = (1 << lastNbits) - 1;
        uint aaveLTV = (bitMap & mask) / 100;
        return int(aaveLTV) - int(LTV_BUFFER);
    }


    function calculateNeededCollateral(uint _shortTokenAmount) internal view returns (uint) {
        uint shortTokenDecimals = IwERC20(SHORT_TOKEN).decimals();
        uint baseTokenDecimals = IwERC20(BASE_TOKEN).decimals();
        uint baseTokenConversion = 10 ** (18 - baseTokenDecimals);

        uint priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN) / baseTokenConversion;   // Units: base token decimals               
        uint amountShortTokenBase = (_shortTokenAmount * priceOfShortTokenInBase).dividedBy(10 ** shortTokenDecimals, 0); // Units: base token decimals

        uint shaaveLTV = uint(getShaaveLTV(BASE_TOKEN));

        return (amountShortTokenBase / shaaveLTV) * 100;
    }
}


contract TestShaaveParentData is Test, ShaaveParentHelper {

    // Contracts
    ShaaveParent shaaveParent;

    // Test Events
    event CollateralSuccess(address user, address testBaseTokenAddress , uint amount);

    function setUp() public {
        shaaveParent = new ShaaveParent(10);
    }

    function test_getNeededCollateralAmount(uint amountMultiplier) public {
        /// @dev Assumptions
        vm.assume(amountMultiplier > 0 && amountMultiplier <= 1e2);
        uint shortTokenAmount = SHORT_TOKEN_AMOUNT * amountMultiplier;

        /// @dev Expecations
        uint expectedCollateral = calculateNeededCollateral(shortTokenAmount);

        /// @dev Act
        uint neededCollateral = shaaveParent.getNeededCollateralAmount(SHORT_TOKEN, BASE_TOKEN, shortTokenAmount);

        /// @dev Assertions
        assertEq(neededCollateral, expectedCollateral);
    }

    function testFail_getNeededCollateralAmountInvalidAmount() public view {
        /// @dev Act
        shaaveParent.getNeededCollateralAmount(SHORT_TOKEN, BASE_TOKEN, 0);
    }

}