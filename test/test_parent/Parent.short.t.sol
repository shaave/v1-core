// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import "solmate/utils/SafeTransferLib.sol";
import "@aave-protocol/interfaces/IPool.sol";

import "../../src/parent/Parent.sol";
import "../../src/child/Child.sol";
import "../../src/libraries/AddressLib.sol";
import "../../src/interfaces/IChild.sol";
import "../common/ChildUtils.t.sol";

contract ShortTest is ChildUtils, TestUtils {
    using AddressLib for address[];

    address retrievedBaseToken;
    address[] children;
    address[] baseTokens;

    uint256 expectedChildCount;
    uint256 preActionChildCount;
    uint256 postActionChildCount;

    // Contracts
    Parent shaaveParent;

    function setUp() public {
        shaaveParent = new Parent(10);
    }

    /// @dev tests that child contracts get created, in accordance with first-time shorts
    function test_addShortPosition_child_creation() public {
        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            address baseToken = reserves[i];
            if (!BANNED_COLLATERAL.includes(baseToken)) {
                if (baseToken != SHORT_TOKEN) {
                    // Setup
                    uint256 baseTokenAmount = (10 ** IERC20Metadata(baseToken).decimals()); // 1 unit in correct decimals
                    deal(baseToken, address(this), baseTokenAmount);
                    SafeTransferLib.safeApprove(ERC20(baseToken), address(shaaveParent), baseTokenAmount);

                    // Expectations
                    address child = shaaveParent.userContracts(address(this), baseToken);
                    assertEq(child, address(0), "child should not exist, but does.");

                    // Act
                    shaaveParent.addShortPosition(SHORT_TOKEN, baseToken, baseTokenAmount);

                    // Assertions
                    child = shaaveParent.userContracts(address(this), baseToken);
                    assertEq(IChild(child).baseToken(), baseToken, "Incorrect baseToken address on child.");
                }
            }
        }
    }

    /// @dev tests that existing child is utilized for non-first shorts
    function test_addShortPosition_not_first() public {
        uint256 amountMultiplier = 1;
        // Setup
        uint256 baseTokenAmount = (10 ** IERC20Metadata(USDC_ADDRESS).decimals()) * amountMultiplier; // 1 unit in correct decimals * amountMultiplier
        deal(USDC_ADDRESS, address(this), baseTokenAmount);
        SafeTransferLib.safeApprove(ERC20(USDC_ADDRESS), address(shaaveParent), baseTokenAmount);

        // Expectations 1
        uint256 borrowAmount_1 = getBorrowAmount(baseTokenAmount / 2, USDC_ADDRESS);
        (, uint256 amountOut_1) = swapExactInput(SHORT_TOKEN, USDC_ADDRESS, borrowAmount_1);

        // Act 1: short using USDC
        shaaveParent.addShortPosition(SHORT_TOKEN, USDC_ADDRESS, baseTokenAmount / 2);

        // Data extraction 1
        address child = shaaveParent.userContracts(address(this), USDC_ADDRESS);
        Child.PositionData[] memory accountingData = IChild(child).getAccountingData();

        // Expectations 2
        uint256 borrowAmount_2 = getBorrowAmount(baseTokenAmount / 2, USDC_ADDRESS);
        (, uint256 amountOut_2) = swapExactInput(SHORT_TOKEN, USDC_ADDRESS, borrowAmount_2);

        // Act 2: short using USDC again
        vm.warp(block.timestamp + 120);
        shaaveParent.addShortPosition(SHORT_TOKEN, USDC_ADDRESS, baseTokenAmount / 2);

        // Data extraction 2 (using same child from first short)
        accountingData = IChild(child).getAccountingData();

        // Assertions: ensure accounting data reflects more than one short
        assertEq(accountingData[0].shortTokenAmountsSwapped.length, 2, "Incorrect shortTokenAmountsSwapped length.");
        assertEq(accountingData[0].backingBaseAmount, amountOut_1 + amountOut_2, "Incorrect backingBaseAmount.");
    }

    /// @dev tests that child contract accounting data gets updated properly after a short position is opened
    function test_addShortPosition_accounting(uint256 amountMultiplier) public {
        // Assumptions
        vm.assume(amountMultiplier > 0 && amountMultiplier <= 1000);

        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            address baseToken = reserves[i];
            if (!BANNED_COLLATERAL.includes(baseToken)) {
                if (reserves[i] != SHORT_TOKEN) {
                    // Setup
                    uint256 baseTokenAmount = (10 ** IERC20Metadata(baseToken).decimals()) * amountMultiplier; // 1 unit in correct decimals * amountMultiplier
                    deal(baseToken, address(this), baseTokenAmount);
                    SafeTransferLib.safeApprove(ERC20(baseToken), address(shaaveParent), baseTokenAmount);

                    // Expectations
                    uint256 borrowAmount = getBorrowAmount(baseTokenAmount, baseToken);
                    (uint256 amountIn, uint256 amountOut) = swapExactInput(SHORT_TOKEN, baseToken, borrowAmount);

                    // Act
                    shaaveParent.addShortPosition(SHORT_TOKEN, baseToken, baseTokenAmount);

                    // Post-action data extraction
                    address child = shaaveParent.userContracts(address(this), baseToken);
                    Child.PositionData[] memory accountingData = IChild(child).getAccountingData();
                    (uint256 aTokenBalance, uint256 debtTokenBalance, uint256 baseTokenBalance, uint256 userBaseBalance)
                    = getTokenData(child, baseToken);

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
                    assertEq(accountingData[0].collateralAmounts[0], baseTokenAmount, "Incorrect collateralAmounts.");
                    assertEq(accountingData[0].backingBaseAmount, amountOut, "Incorrect backingBaseAmount.");
                    assertEq(accountingData[0].shortTokenAddress, SHORT_TOKEN, "Incorrect shortTokenAddress.");
                    assertEq(accountingData[0].hasDebt, true, "Incorrect hasDebt.");

                    // Token balances
                    uint256 acceptableTolerance = 3;
                    int256 collateralDiff = int256(baseTokenAmount) - int256(aTokenBalance);
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
