// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Foundry
import "forge-std/Test.sol";
import "forge-std/console.sol";

// Local file imports
import "../../src/child/Child.sol";
import "../../src/interfaces/IERC20Metadata.sol";
import ".././mocks/MockUniswap.t.sol";
import "./common/TestSetup.t.sol";
import "../common/constants.t.sol";


contract SellAllTest is ShaaveChildHelper {

    // Contracts
    Child testShaaveChild;

    // Events
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);

    
    function setUp() public {
        // Instantiate Child
        testShaaveChild = new Child(address(this), BASE_TOKEN, IERC20Metadata(BASE_TOKEN).decimals(), getShaaveLTV(BASE_TOKEN));

        // Add short position, so we can sell
        deal(BASE_TOKEN, address(testShaaveChild), TEST_COLLATERAL_AMOUNT);
        bool success = testShaaveChild.short(SHORT_TOKEN, TEST_COLLATERAL_AMOUNT, address(this));
        assert(success);

        // Post short assertions
        Child.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
        assertEq(preAccountingData.length, 1);
        assertEq(preAccountingData[0].shortTokenAmountsSwapped.length, 1);
        assertEq(preAccountingData[0].baseAmountsReceived.length, 1);
        assertEq(preAccountingData[0].collateralAmounts.length, 1);
        assertEq(preAccountingData[0].baseAmountsSwapped.length, 0);
        assertEq(preAccountingData[0].shortTokenAmountsReceived.length, 0);
    }

    function test_reduecePosition_all_single() public {
        /// @dev Pre-action data extraction
        Child.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();

        /// @dev Expectations
        uint baseTokenConversion = 10 ** (18 - IERC20Metadata(BASE_TOKEN).decimals());
        (uint amountIn, uint amountOut) = swapToShortToken(SHORT_TOKEN, BASE_TOKEN, preAccountingData[0].shortTokenAmountsSwapped[0], preAccountingData[0].backingBaseAmount, baseTokenConversion);
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit SwapSuccess(address(this), BASE_TOKEN, amountIn, SHORT_TOKEN, amountOut);

        /// @dev Act
        vm.warp(block.timestamp + 120);    // Trick Aave into thinking it's not a flash loan ;)
        assert(testShaaveChild.reducePosition(SHORT_TOKEN, 100, true));

        /// @dev Post-action data extraction
        Child.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) = getTokenData(address(testShaaveChild), BASE_TOKEN);

        /// @dev Assertions
        // Length
        assertEq(postAccountingData.length, 1);
        assertEq(postAccountingData[0].baseAmountsReceived.length, 1);
        assertEq(postAccountingData[0].collateralAmounts.length, 1);
        assertEq(postAccountingData[0].baseAmountsSwapped.length, 1);
        assertEq(postAccountingData[0].shortTokenAmountsReceived.length, 1); 
        assertEq(postAccountingData[0].shortTokenAmountsSwapped.length, 1);
        // Values
        // Esnure this data updated
        assertEq(postAccountingData[0].baseAmountsSwapped[0], amountIn);
        assertEq(postAccountingData[0].shortTokenAmountsReceived[0], amountOut);
        assertEq(postAccountingData[0].backingBaseAmount, 0);
        // Esnure this data stayed the same
        assertEq(postAccountingData[0].shortTokenAmountsSwapped[0], preAccountingData[0].shortTokenAmountsSwapped[0]);
        assertEq(postAccountingData[0].baseAmountsReceived[0], preAccountingData[0].baseAmountsReceived[0]);
        assertEq(postAccountingData[0].collateralAmounts[0], preAccountingData[0].collateralAmounts[0]);
        assertEq(postAccountingData[0].shortTokenAddress, preAccountingData[0].shortTokenAddress);

        // Enure correct resulting token balances
        uint baseTolerance = 10000;  // USDC Units: 6 decimals
        uint debtTolerance = 1000;
        int baseTokenDiff = int(userBaseBalance) - int(TEST_COLLATERAL_AMOUNT);
        uint baseTokenDiffAbs = baseTokenDiff < 0 ? uint(-baseTokenDiff) : uint(baseTokenDiff);
        assert(debtTokenBalance < debtTolerance);
        assert(aTokenBalance <= baseTolerance);
        assertEq(baseTokenBalance, 0);
        assert(baseTokenDiffAbs <= baseTolerance);
    }

    function test_reduecePosition_single_close_out_with_profit() public {
        /// @dev Pre-action assertions
        Child.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();

        /// @dev Expectations
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit SwapSuccess(address(this), BASE_TOKEN, UNISWAP_AMOUNT_IN_PROFIT, SHORT_TOKEN, preAccountingData[0].shortTokenAmountsSwapped[0]);

        /// @dev Mock Uniswap, such that we can ensure a profit.  
        deal(SHORT_TOKEN, UNISWAP_SWAP_ROUTER, preAccountingData[0].shortTokenAmountsSwapped[0]);
        bytes memory MockUniswapGainsCode = address(new MockUniswapGains()).code;
        vm.etch(UNISWAP_SWAP_ROUTER, MockUniswapGainsCode);

        /// @dev Act
        vm.warp(block.timestamp + 120);    // Trick Aave into thinking it's not a flash loan ;)
        bool success = testShaaveChild.reducePosition(SHORT_TOKEN, 100, true);

        /// @dev Post-action data extraction
        Child.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) = getTokenData(address(testShaaveChild), BASE_TOKEN);

        /// @dev Assertions
        assert(success);
        // Length
        assertEq(postAccountingData.length, 1);
        assertEq(postAccountingData[0].shortTokenAmountsSwapped.length, 1);
        assertEq(postAccountingData[0].baseAmountsReceived.length, 1);
        assertEq(postAccountingData[0].collateralAmounts.length, 1);
        assertEq(postAccountingData[0].baseAmountsSwapped.length, 1);
        assertEq(postAccountingData[0].shortTokenAmountsReceived.length, 1);
        // Values
        // Esnure this data updated
        assertEq(postAccountingData[0].baseAmountsSwapped[0], UNISWAP_AMOUNT_IN_PROFIT);
        assertEq(postAccountingData[0].shortTokenAmountsReceived[0], preAccountingData[0].shortTokenAmountsSwapped[0]);
        assertEq(postAccountingData[0].backingBaseAmount, 0);
        assertEq(postAccountingData[0].hasDebt, false);
        // Esnure this data stayed the same
        assertEq(postAccountingData[0].shortTokenAmountsSwapped[0], preAccountingData[0].shortTokenAmountsSwapped[0]);
        assertEq(postAccountingData[0].baseAmountsReceived[0], preAccountingData[0].baseAmountsReceived[0]);
        assertEq(postAccountingData[0].collateralAmounts[0], preAccountingData[0].collateralAmounts[0]);
        assertEq(postAccountingData[0].shortTokenAddress, preAccountingData[0].shortTokenAddress);
        

        // Enure correct resulting token balances
        assertEq(debtTokenBalance, 0);
        assert(aTokenBalance < 1500);
        assertEq(baseTokenBalance, 0);
        assert(userBaseBalance > TEST_COLLATERAL_AMOUNT); // There were gains
    }

    function test_reduecePosition_single_close_out_losses() public {
        /// @dev Pre-action assertions
        Child.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
    
        /// @dev Expectations
        uint neededAmountOut = preAccountingData[0].shortTokenAmountsSwapped[0] / UNISWAP_AMOUNT_OUT_LOSSES_FACTOR;
        uint borrowAmount = getBorrowAmount(TEST_COLLATERAL_AMOUNT, BASE_TOKEN);
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit SwapSuccess(address(this), BASE_TOKEN, preAccountingData[0].backingBaseAmount, SHORT_TOKEN, neededAmountOut);

        /// @dev Mock Uniswap, such that we can ensure a loss.
        
        deal(SHORT_TOKEN, UNISWAP_SWAP_ROUTER, neededAmountOut);
        bytes memory MockUniswapLossesCode = address(new MockUniswapLosses()).code;
        vm.etch(UNISWAP_SWAP_ROUTER, MockUniswapLossesCode);

        /// @dev Act
        vm.warp(block.timestamp + 120);    // Trick Aave into thinking it's not a flash loan ;)
        bool success = testShaaveChild.reducePosition(SHORT_TOKEN, 100, true);

        /// @dev Post-action data extraction
        Child.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) = getTokenData(address(testShaaveChild), BASE_TOKEN);

        /// @dev Assertions
        assert(success);
        // Length
        assertEq(postAccountingData.length, 1);
        assertEq(postAccountingData[0].shortTokenAmountsSwapped.length, 1);
        assertEq(postAccountingData[0].baseAmountsReceived.length, 1);
        assertEq(postAccountingData[0].collateralAmounts.length, 1);
        assertEq(postAccountingData[0].baseAmountsSwapped.length, 1);
        assertEq(postAccountingData[0].shortTokenAmountsReceived.length, 1);
        // Values
        // Esnure this data updated
        assertEq(postAccountingData[0].baseAmountsSwapped[0],  preAccountingData[0].backingBaseAmount);
        assert(postAccountingData[0].shortTokenAmountsReceived[0] < preAccountingData[0].shortTokenAmountsSwapped[0]);
        assertEq(postAccountingData[0].backingBaseAmount, 0);
        
        // Esnure this data stayed the same
        assertEq(postAccountingData[0].shortTokenAmountsSwapped[0], preAccountingData[0].shortTokenAmountsSwapped[0]);
        assertEq(postAccountingData[0].baseAmountsReceived[0], preAccountingData[0].baseAmountsReceived[0]);
        assertEq(postAccountingData[0].collateralAmounts[0], preAccountingData[0].collateralAmounts[0]);
        assertEq(postAccountingData[0].shortTokenAddress, preAccountingData[0].shortTokenAddress);
        assertEq(postAccountingData[0].hasDebt, true);
        

        // Enure correct resulting token balances
        assert(debtTokenBalance >= borrowAmount / UNISWAP_AMOUNT_OUT_LOSSES_FACTOR);
        assert(aTokenBalance >= TEST_COLLATERAL_AMOUNT / UNISWAP_AMOUNT_OUT_LOSSES_FACTOR);
        assertEq(baseTokenBalance, 0);
        assert(userBaseBalance < TEST_COLLATERAL_AMOUNT); // There were losses
    }


    function testCannot_reduecePosition_amount(uint percentageReduction) public {
        vm.assume(percentageReduction > 100);

        /// @dev Expectations
        vm.expectRevert("Invalid percentage.");

        /// @dev Act
        testShaaveChild.reducePosition(SHORT_TOKEN, percentageReduction, true);
    }
}

contract SellSomeTest is Test, ShaaveChildHelper {

    // Contracts
    Child testShaaveChild;

    // Events
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);

    function setUp() public {
        // Instantiate Child
        testShaaveChild = new Child(address(this), BASE_TOKEN, IERC20Metadata(BASE_TOKEN).decimals(), getShaaveLTV(BASE_TOKEN));

        // Add short position, so we can sell
        deal(BASE_TOKEN, address(testShaaveChild), TEST_COLLATERAL_AMOUNT);
        assert(testShaaveChild.short(SHORT_TOKEN, TEST_COLLATERAL_AMOUNT, address(this)));

        // Post short assertions
        Child.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
        assertEq(preAccountingData.length, 1);
        assertEq(preAccountingData[0].shortTokenAmountsSwapped.length, 1);
        assertEq(preAccountingData[0].baseAmountsReceived.length, 1);
        assertEq(preAccountingData[0].collateralAmounts.length, 1);
        assertEq(preAccountingData[0].baseAmountsSwapped.length, 0);
        assertEq(preAccountingData[0].shortTokenAmountsReceived.length, 0);
    }

    function test_reduecePosition_some_single(uint reductionPercentage) public {
        /// @dev Assumptions
        vm.assume(reductionPercentage > 0 && reductionPercentage <= 100);

        /// @dev Pre-action data extraction
        Child.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
        (uint pre_aTokenBalance, uint pre_debtTokenBalance, , ) = getTokenData(address(testShaaveChild), BASE_TOKEN);

        /// @dev Expectations
        uint positionReduction = (getOutstandingDebt(SHORT_TOKEN, address(testShaaveChild)) * reductionPercentage) / 100;
        uint initialBackingBaseAmount = preAccountingData[0].backingBaseAmount;
        (uint amountIn, uint amountOut) = swapToShortToken(SHORT_TOKEN, BASE_TOKEN, positionReduction, initialBackingBaseAmount, testShaaveChild.baseTokenConversion());
        uint expectedGains = getGains(preAccountingData[0].backingBaseAmount, amountIn, testShaaveChild.baseTokenConversion(), reductionPercentage, address(testShaaveChild));
        uint expectedWithdrawal = getWithdrawal(address(testShaaveChild), amountOut);
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit SwapSuccess(address(this), BASE_TOKEN, amountIn, SHORT_TOKEN, amountOut);

        /// @dev Act
        vm.warp(block.timestamp + 120);    // Trick Aave into thinking it's not a flash loan ;)
        assert(testShaaveChild.reducePosition(SHORT_TOKEN, reductionPercentage, true));

        /// @dev Post-action data extraction
        Child.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, , ) = getTokenData(address(testShaaveChild), BASE_TOKEN);
        

        /// @dev Assertions
        // Length
        assertEq(postAccountingData.length, 1);
        assertEq(postAccountingData[0].baseAmountsReceived.length, 1);
        assertEq(postAccountingData[0].collateralAmounts.length, 1);
        assertEq(postAccountingData[0].baseAmountsSwapped.length, 1);
        assertEq(postAccountingData[0].shortTokenAmountsReceived.length, 1); 
        assertEq(postAccountingData[0].shortTokenAmountsSwapped.length, 1);
        // Values
        // Esnure this data updated
        assertEq(postAccountingData[0].baseAmountsSwapped[0], amountIn);
        assertEq(postAccountingData[0].shortTokenAmountsReceived[0], amountOut);
        assertEq(postAccountingData[0].backingBaseAmount, initialBackingBaseAmount - (amountIn + expectedGains));
        // Esnure this data stayed the same
        assertEq(postAccountingData[0].shortTokenAmountsSwapped[0], preAccountingData[0].shortTokenAmountsSwapped[0]);
        assertEq(postAccountingData[0].baseAmountsReceived[0], preAccountingData[0].baseAmountsReceived[0]);
        assertEq(postAccountingData[0].collateralAmounts[0], preAccountingData[0].collateralAmounts[0]);
        assertEq(postAccountingData[0].shortTokenAddress, preAccountingData[0].shortTokenAddress);

        // Enure correct resulting token balances    
        int debtDiff = int(debtTokenBalance) - int(pre_debtTokenBalance - amountOut); // epectedDebt = pre_debtTokenBalance - amountOut
        uint debtDiffAbs = debtDiff < 0 ? uint(-debtDiff) : uint(debtDiff);

        uint expectedATokens = pre_aTokenBalance - expectedWithdrawal / testShaaveChild.baseTokenConversion();
        int aTokenDiff = int(aTokenBalance) - int(expectedATokens);
        uint aTokenDiffAbs = aTokenDiff < 0 ? uint(-aTokenDiff) : uint(aTokenDiff);

        assert(debtDiffAbs <= 10);   // An arbitrary maximum tolerance (0.00001%)
        assert(aTokenDiffAbs <= 10); // An arbitrary maximum tolerance (0.001%)
        assertEq(IERC20(BASE_TOKEN).balanceOf(address(testShaaveChild)), postAccountingData[0].backingBaseAmount);
        assertEq(IERC20(BASE_TOKEN).balanceOf(address(this)), (expectedGains + expectedWithdrawal) / testShaaveChild.baseTokenConversion());
    }
}
