// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/contracts/libraries/ReturnCapital.sol";
import "../../src/contracts/libraries/ShaavePricing.sol";
import "../../src/contracts/libraries/Math.sol";
import "../common/constants.t.sol";

// External package imports
import "@aave-protocol/interfaces/IAaveOracle.sol";
import "@aave-protocol/interfaces/IPool.sol";


import "forge-std/console.sol";


contract ReturnCapitalHelper {
    uint constant public ltvBuffer = 10;

    function getShaaveLTV(address baseToken) internal view returns (uint) {
        uint bitMap = IPool(AAVE_POOL).getReserveData(baseToken).configuration.data;
        uint lastNbits = 16;               // bit 0-15: LTV
        uint mask = (1 << lastNbits) - 1;
        uint aaveLTV = (bitMap & mask) / 100;
        return aaveLTV - ltvBuffer;
    }
}


contract TestReturnCapital is Test, ReturnCapitalHelper {
    using Math for uint;
    using ShaavePricing for address;

    uint constant FULL_REDUCTION = 100;
    uint constant TEST_SHORT_TOKEN_DEBT = 100e18;    // 100 tokens

    /*******************************************************************************
    **
    **  getPositionGains tests
    **
    *******************************************************************************/

    function test_getPositionGains_noGains(uint valueLost) public {
        
        // Setup
        uint priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN);         // Wei
        uint debtValueInBase = (priceOfShortTokenInBase * TEST_SHORT_TOKEN_DEBT) / 1e18;         // Wei
        vm.assume(valueLost <= debtValueInBase);
        uint positionBackingBaseAmount = debtValueInBase - valueLost;

        // Act
        uint gains = ReturnCapital.getPositionGains(SHORT_TOKEN, BASE_TOKEN, FULL_REDUCTION, positionBackingBaseAmount, TEST_SHORT_TOKEN_DEBT);

        // Assertions
        assertEq(gains, 0);
    }

    function test_getPositionGains_gains(uint valueAccrued) public {
        vm.assume(valueAccrued < 1e9);
        // Setup
        uint priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN);         // Wei
        uint debtValueInBase = (priceOfShortTokenInBase * TEST_SHORT_TOKEN_DEBT) / 1e18;         // Wei
        uint positionBackingBaseAmount = debtValueInBase + valueAccrued;

        // Act
        uint gains = ReturnCapital.getPositionGains(SHORT_TOKEN, BASE_TOKEN, FULL_REDUCTION, positionBackingBaseAmount, TEST_SHORT_TOKEN_DEBT);

        // Assertions
        assertEq(gains, valueAccrued);
    }

    /*******************************************************************************
    **
    **  getMaxWithdrawal tests
    **
    *******************************************************************************/

    function test_getMaxWithdrawal_zeroWithdrawal() public {
        // Act
        uint withdrawalAmount = ReturnCapital.getMaxWithdrawal(CHILD_ADDRESS, getShaaveLTV(BASE_TOKEN));
        
        // Assertions
        assertEq(withdrawalAmount, 0);
    }


    // TODO: Since this function depends on shorts open, need to test that functionality first before testing this.
    // function test_getMaxWithdrawal_zeroWithdrawal_nonZeroWithdrawal() public {
    //     // Setup
    //     address[] memory reserves = IPool(AAVE_POOL).getReservesList();
    //     uint    totalCollateralBase    = 55e8;
    //     uint    totalDebtBase          = 7e8;
    //     uint    ShaaveDebtToCollateral = 70;
    //     uint    maxUncapturedDebt      = 9999999999;
    //     uint    uncapturedCollateral   = (maxUncapturedDebt.dividedBy(ShaaveDebtToCollateral,0) * 100);
    //     uint    expectedWithdrawAmount = ((totalCollateralBase - (totalDebtBase.dividedBy(ShaaveDebtToCollateral, 0) * 100)) * 1e10) - uncapturedCollateral;


    //     for (uint i; i < reserves.length; i++) {
    //         uint shaaveLTV = getShaaveLTV(reserves[i]);


    //         // Act
    //         uint actualwithdrawalAmount = ReturnCapital.getMaxWithdrawal(CHILD_ADDRESS);


    //         // Assertions
    //         assertEq(actualwithdrawalAmount, expectedWithdrawAmount);
    //     }
    // }
}