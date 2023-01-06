// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Foundry
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aave-protocol/interfaces/IPool.sol";
//import "@aave-protocol/interfaces/IPoolDataProvider.sol";

// Local file imports
import "../../src/child/Child.sol";
import "../../src/interfaces/IERC20Metadata.sol";
import "./common/TestSetup.t.sol";
import "../common/constants.t.sol";

/* TODO: The following still needs to be tested here:
1. XXX Reduce position: Test actual runthrough without mock
2. XXX Reduce position 100% with no gains, and ensure no gains (easy)
3. XXX Reduce position by < 100%, with gains, and ensure correct amount gets paid
4. Reduce position by < 100%, with no gains and ensure no gains
5. Try to short with all supported collateral -- nested for loop for short tokens?
6. Then, parent can be tested*/

contract ShortTest is ShaaveChildHelper {
    using AddressArray for address[];

    // Contracts
    Child testShaaveChild;

    // Test Variables
    // Polygon banned list
    address[] BANNED_BORROW = [
        0xD6DF932A45C0f255f85145f286eA0b292B21C90B,
        0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4,
        0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6
    ];
    address[] BANNED_COLLATERAL = [
        0xE0B52e49357Fd4DAf2c15e02058DCE6BC0057db4,
        0xE111178A87A3BFf0c8d18DECBa5798827539Ae99,
        0x4e3Decbb3645551B8A19f0eA1678079FCB33fB4c,
        0xa3Fa99A148fA48D14Ed51d610c367C61876997F1,
        0xc2132D05D31c914a87C6611C10748AEb04B58e8F,
        0x172370d5Cd63279eFa6d502DAB29171933a610AF,
        0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a,
        0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7,
        0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3,
        0x85955046DF4668e1DD369D2DE9f3AEB98DD2A369,
        0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6,
        0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4
    ];

    // Events
    event BorrowSuccess(address user, address borrowTokenAddress, uint256 amount);
    event SwapSuccess(
        address user, address tokenInAddress, uint256 tokenInAmount, address tokenOutAddress, uint256 tokenOutAmount
    );
    event PositionAddedSuccess(address user, address shortTokenAddress, uint256 amount);

    function setUp() public {
        // Instantiate Child
        testShaaveChild =
            new Child(address(this), BASE_TOKEN, IERC20Metadata(BASE_TOKEN).decimals(), getShaaveLTV(BASE_TOKEN));
    }

    // All collaterals; shorting BTC
    function test_short_all(uint256 amountMultiplier) public {
        vm.assume(amountMultiplier > 0 && amountMultiplier <= 1e3);

        // Assumptions:
        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            address testBaseToken = reserves[i];
            if (!BANNED_COLLATERAL.includes(reserves[i])) {
                // Instantiate Child
                testShaaveChild =
                new Child(address(this), testBaseToken, IERC20Metadata(testBaseToken).decimals(), getShaaveLTV(testBaseToken));

                // Setup
                uint256 collateralAmount = (10 ** IERC20Metadata(reserves[i]).decimals()) * amountMultiplier; // 1 uint in correct decimals

                // Supply
                if (testBaseToken != SHORT_TOKEN) {
                    // Setup
                    deal(testBaseToken, address(testShaaveChild), collateralAmount);

                    // Expectations
                    uint256 borrowAmount = getBorrowAmount(collateralAmount, testBaseToken);
                    (uint256 amountIn, uint256 amountOut) = swapExactInput(SHORT_TOKEN, testBaseToken, borrowAmount);
                    vm.expectEmit(true, true, true, true, address(testShaaveChild));
                    emit BorrowSuccess(address(this), SHORT_TOKEN, borrowAmount);
                    vm.expectEmit(true, true, true, true, address(testShaaveChild));
                    emit SwapSuccess(address(this), SHORT_TOKEN, amountIn, testBaseToken, amountOut);
                    vm.expectEmit(true, true, true, true, address(testShaaveChild));
                    emit PositionAddedSuccess(address(this), SHORT_TOKEN, borrowAmount);

                    // Act
                    testShaaveChild.short(SHORT_TOKEN, collateralAmount, address(this));

                    // Post-action data extraction
                    Child.PositionData[] memory accountingData = testShaaveChild.getAccountingData();
                    (uint256 aTokenBalance, uint256 debtTokenBalance, uint256 baseTokenBalance, uint256 userBaseBalance)
                    = getTokenData(address(testShaaveChild), testBaseToken);

                    // Assertions
                    // Length
                    assertEq(accountingData.length, 1, "Incorrect accountingData length.");
                    assertEq(
                        accountingData[0].shortTokenAmountsSwapped.length,
                        1,
                        "Incorrect shortTokenAmountsSwapped length."
                    );
                    assertEq(accountingData[0].baseAmountsReceived.length, 1, "Incorrect baseAmountsReceived length.");
                    assertEq(accountingData[0].collateralAmounts.length, 1, "Incorrect collateralAmounts length.");
                    assertEq(accountingData[0].baseAmountsSwapped.length, 0, "Incorrect baseAmountsSwapped length.");
                    assertEq(
                        accountingData[0].shortTokenAmountsReceived.length,
                        0,
                        "Incorrect shortTokenAmountsReceived length."
                    );

                    // Values
                    assertEq(
                        accountingData[0].shortTokenAmountsSwapped[0], amountIn, "Incorrect shortTokenAmountsSwapped."
                    );
                    assertEq(accountingData[0].baseAmountsReceived[0], amountOut, "Incorrect baseAmountsReceived.");
                    assertEq(accountingData[0].collateralAmounts[0], collateralAmount, "Incorrect collateralAmounts.");
                    assertEq(accountingData[0].backingBaseAmount, amountOut, "Incorrect backingBaseAmount.");
                    assertEq(accountingData[0].shortTokenAddress, SHORT_TOKEN, "Incorrect shortTokenAddress.");
                    assertEq(accountingData[0].hasDebt, true, "Incorrect hasDebt.");

                    // Test Aave tokens
                    uint256 acceptableTolerance = 3;
                    int256 collateralDiff = int256(collateralAmount) - int256(aTokenBalance);
                    uint256 collateralDiffAbs = collateralDiff < 0 ? uint256(-collateralDiff) : uint256(collateralDiff);
                    int256 debtDiff = int256(amountIn) - int256(debtTokenBalance);
                    uint256 debtDiffAbs = debtDiff < 0 ? uint256(-debtDiff) : uint256(debtDiff);
                    assert(collateralDiffAbs <= acceptableTolerance); // Small tolerance, due to potential interest
                    assert(debtDiffAbs <= acceptableTolerance); // Small tolerance, due to potential interest
                    assertEq(baseTokenBalance, amountOut, "Incorrect baseTokenBalance.");
                    assertEq(userBaseBalance, 0, "Incorrect baseTokenBalance.");
                }
            }
        }
    }
}
