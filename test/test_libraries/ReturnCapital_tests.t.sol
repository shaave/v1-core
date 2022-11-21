// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/contracts/libraries/ReturnCapital.sol";
import "../../src/contracts/libraries/ShaavePricing.sol";
import "../../src/contracts/libraries/Math.sol";
import "../common/constants.t.sol";

// External package imports
import "@aave-protocol/interfaces/IAaveOracle.sol";

contract Test_ReturnCapital is Test {
    using Math for uint;
    using ShaavePricing for address;

    uint constant FULL_REDUCTION = 100;
    uint constant TEST_SHORT_TOKEN_DEBT = 100e18;    // 100 tokens

    /*******************************************************************************
    **
    **  calculatePositionGains tests
    **
    *******************************************************************************/

    function test_calculatePositionGains_noGains(uint valueLost) public {
        
        // Setup
        uint priceOfShortTokenInBase = SHORT_TOKEN_ADDRESS.pricedIn(BASE_TOKEN_ADDRESS);         // Wei
        uint debtValueInBase = (priceOfShortTokenInBase * TEST_SHORT_TOKEN_DEBT) / 1e18;         // Wei
        vm.assume(valueLost <= debtValueInBase);
        uint positionBackingBaseAmount = debtValueInBase - valueLost;

        // Act
        uint gains = ReturnCapital.calculatePositionGains(SHORT_TOKEN_ADDRESS, BASE_TOKEN_ADDRESS, FULL_REDUCTION, positionBackingBaseAmount, TEST_SHORT_TOKEN_DEBT);

        // Assertions
        assertEq(gains, 0);
    }

    function test_calculatePositionGains_gains(uint valueAccrued) public {
        vm.assume(valueAccrued < 1e9);
        // Setup
        uint priceOfShortTokenInBase = SHORT_TOKEN_ADDRESS.pricedIn(BASE_TOKEN_ADDRESS);         // Wei
        uint debtValueInBase = (priceOfShortTokenInBase * TEST_SHORT_TOKEN_DEBT) / 1e18;         // Wei
        uint positionBackingBaseAmount = debtValueInBase + valueAccrued;

        // Act
        uint gains = ReturnCapital.calculatePositionGains(SHORT_TOKEN_ADDRESS, BASE_TOKEN_ADDRESS, FULL_REDUCTION, positionBackingBaseAmount, TEST_SHORT_TOKEN_DEBT);

        // Assertions
        assertEq(gains, valueAccrued);
    }

    /*******************************************************************************
    **
    **  calculateCollateralWithdrawAmount tests
    **
    *******************************************************************************/

    function test_calculateCollateralWithdrawAmount_zeroWithdrawal() public {
        // Act
        uint withdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(CHILD_ADDRESS);
        
        // Assertions
        assertEq(withdrawalAmount, 0);
    }

    function test_calculateCollateralWithdrawAmount_zeroWithdrawal_nonZeroWithdrawal() public {
        // Setup
        uint    totalCollateralBase    = 55e8;
        uint    totalDebtBase          = 7e8;
        uint    ShaaveDebtToCollateral = 70;
        uint    maxUncapturedDebt      = 9999999999;
        uint    uncapturedCollateral   = (maxUncapturedDebt.dividedBy(ShaaveDebtToCollateral,0) * 100);
        uint    expectedWithdrawAmount = ((totalCollateralBase - (totalDebtBase.dividedBy(ShaaveDebtToCollateral, 0) * 100)) * 1e10) - uncapturedCollateral;

        // Act
        uint actualwithdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(CHILD_ADDRESS);

        // Assertions
        assertEq(actualwithdrawalAmount, expectedWithdrawAmount);
    }
}