// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Foundry
import "forge-std/Test.sol";
import "forge-std/console.sol";

// External packages
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";
import "@aave-protocol/interfaces/IPool.sol";

// Local file imports
import "../src/contracts/ShaaveChild.sol";
import "./mocks/MockUniswap.t.sol";
import "./common/constants.t.sol";


/* TODO: The following still needs to be tested here:
1. XXX Reduce position: Test actual runthrough without mock
2. XXX Reduce position 100% with no gains, and ensure no gains (easy)
3. XXX Reduce position by < 100%, with gains, and ensure correct amount gets paid
4. Reduce position by < 100%, with no gains and ensure no gains
5. Try to short with all supported collateral -- nested for loop for short tokens?
6. Then, parent can be tested
*/


contract UniswapHelper is Test {
    using ShaavePricing for address;

    /// @dev This is a test function for computing expected results
    function swapExactInput(
        address _inputToken,
        address _outputToken,
        uint _tokenInAmount
    ) internal returns (uint amountIn, uint amountOut) {
        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        deal(SHORT_TOKEN, address(this), _tokenInAmount);

        ISwapRouter SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _tokenInAmount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _inputToken,
                tokenOut: _outputToken,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _tokenInAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        (amountIn, amountOut) = (_tokenInAmount, SWAP_ROUTER.exactInputSingle(params));

        // Revert to previous snapshot, as if swap never happend
        vm.revertTo(id);
    }

    /// @dev This is a test function for computing expected results
    function swapToShortToken(
        address _outputToken,
        address _inputToken,
        uint _outputTokenAmount,
        uint _inputMax,
        uint baseTokenConversion
    ) internal returns (uint amountIn, uint amountOut) {

        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        // Give this contract (positionBackingBaseAmount) base tokens
        deal(BASE_TOKEN, address(this), _inputMax);
        
        ISwapRouter SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _inputMax);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: _inputToken,
                tokenOut: _outputToken,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: _outputTokenAmount,
                amountInMaximum: _inputMax,
                sqrtPriceLimitX96: 0
            });
        
        try SWAP_ROUTER.exactOutputSingle(params) returns (uint returnedAmountIn) {
            (amountIn, amountOut) = (returnedAmountIn, _outputTokenAmount);
        } catch {
            amountIn = getAmountIn(_outputTokenAmount, _outputToken, _inputMax, baseTokenConversion);
            (amountIn, amountOut) = swapExactInput(_inputToken, _outputToken, amountIn);
        }

        // Revert to previous snapshot, as if swap never happend
        vm.revertTo(id);
    }

    /// @dev This is a test function for computing expected results
    function getAmountIn(uint _positionReduction, address _shortToken, uint _backingBaseAmount, uint baseTokenConversion) internal view returns (uint) {
        /// @dev Units: baseToken decimals
        uint priceOfShortTokenInBase = _shortToken.pricedIn(BASE_TOKEN) / baseTokenConversion;  

        /// @dev Units: baseToken decimals = (baseToken decimals * shortToken decimals) / shortToken decimals
        uint positionReductionBase = (priceOfShortTokenInBase * _positionReduction) / (10 ** IwERC20(_shortToken).decimals());

        if (positionReductionBase <= _backingBaseAmount) {
            return positionReductionBase;
        } else {
            return _backingBaseAmount;
        }
    }
}


contract ShaaveChildHelper is Test, UniswapHelper {
    using ShaavePricing for address;
    using Math for uint;
    
    // Variables
    uint constant public LTV_BUFFER = 10;

    function getShaaveLTV(address _baseToken) internal view returns (uint) {
        uint bitMap = IPool(AAVE_POOL).getReserveData(_baseToken).configuration.data;
        uint aaveLTV = (bitMap & ((1 << 16) - 1)) / 100;  // bit 0-15: LTV
        return aaveLTV - LTV_BUFFER;
    }

    function getAssetDecimals(address _baseToken) internal view returns (uint) {
        uint bitMap = IPool(AAVE_POOL).getReserveData(_baseToken).configuration.data;
        return (((1 << 8) - 1) & (bitMap >> (49-1)));   // bit 48-55: Decimals
    }

    function getBorrowAmount(uint _testCollateralAmount) internal view returns (uint) {
        uint baseTokenConversion = 10 ** (18 - getAssetDecimals(BASE_TOKEN));
        uint shortTokenConversion = 10 ** (18 - getAssetDecimals(SHORT_TOKEN));
        uint priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN);
        uint shaaveLTV = getShaaveLTV(BASE_TOKEN);
        return ((_testCollateralAmount * baseTokenConversion * shaaveLTV) / 100).dividedBy(priceOfShortTokenInBase, 18).dividedBy(shortTokenConversion, 0);
    }

    function getOutstandingDebt(address _shortToken, address _testShaaveChild) internal view returns (uint) {
        address variableDebtTokenAddress = IPool(AAVE_POOL).getReserveData(_shortToken).variableDebtTokenAddress;
        return IERC20(variableDebtTokenAddress).balanceOf(_testShaaveChild);
    }

    function getTokenData(address child) internal view returns (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) {
        address baseAToken = IPool(AAVE_POOL).getReserveData(BASE_TOKEN).aTokenAddress;
        address shortDebtToken = IPool(AAVE_POOL).getReserveData(SHORT_TOKEN).variableDebtTokenAddress;
        aTokenBalance = IERC20(baseAToken).balanceOf(child);
        debtTokenBalance = IERC20(shortDebtToken).balanceOf(child);
        baseTokenBalance = IERC20(BASE_TOKEN).balanceOf(child);
        userBaseBalance = IERC20(BASE_TOKEN).balanceOf(address(this));
    }

    function getGains(uint _backingBaseAmount, uint _amountIn, uint _baseTokenConversion, uint _percentageReduction, address _testShaaveChild) internal view returns (uint gains) {
        uint debtAfterRepay = getOutstandingDebt(SHORT_TOKEN, _testShaaveChild) * (10 ** (18 - getAssetDecimals(SHORT_TOKEN)));      // Wei
        uint backingBaseAmountWei = (_backingBaseAmount - _amountIn) * _baseTokenConversion;

        uint priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN);                      // Wei
        uint debtValueBase = (priceOfShortTokenInBase * debtAfterRepay) / 1e18;               // Wei
        if (backingBaseAmountWei > debtValueBase) {
            gains = (_percentageReduction * (backingBaseAmountWei - debtValueBase)) / 100;    // Wei
        } else {
            gains = 0;
        }
    }

    function getWithdrawal(address _testShaaveChild, uint amountOut) internal returns (uint withdrawalAmount) {
        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        deal(SHORT_TOKEN, address(this), amountOut);
        vm.warp(block.timestamp + 120);    // Trick Aave into thinking it's not a flash loan ;)
        IERC20(SHORT_TOKEN).approve(AAVE_POOL, amountOut);
        IPool(AAVE_POOL).repay(SHORT_TOKEN, amountOut, 2, _testShaaveChild);

        (uint totalCollateralBase, uint totalDebtBase, , , , ) = IPool(AAVE_POOL).getUserAccountData(_testShaaveChild);  // Units: 8 decimals

        uint loanBackingCollateral = ((totalDebtBase / getShaaveLTV(BASE_TOKEN)) * 100);                                      // Wei

        if (totalCollateralBase > loanBackingCollateral){
            withdrawalAmount = ((totalCollateralBase - loanBackingCollateral) * 1e10) - WITHDRAWAL_BUFFER;      // Wei
        } else {
            withdrawalAmount = 0;
        }

        // Revert to previous snapshot, as if repay never happened
        vm.revertTo(id);
    }
}


contract TestChildShort is Test, ShaaveChildHelper {

    // Contracts
    ShaaveChild testShaaveChild;

    // Events
    event BorrowSuccess(address user, address borrowTokenAddress, uint amount);
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);
    event PositionAddedSuccess(address user, address shortTokenAddress, uint amount);

    function setUp() public {
        // Instantiate Child
        testShaaveChild = new ShaaveChild(address(this), BASE_TOKEN, getAssetDecimals(BASE_TOKEN), getShaaveLTV(BASE_TOKEN));
    }

    function test_short_single(uint amountMultiplier) public {
        /// @dev Assuptions:
        vm.assume(amountMultiplier > 0 && amountMultiplier <= 1e6);
        uint collateralAmount = TEST_COLLATERAL_AMOUNT * amountMultiplier;

        /// @dev Setup: supply on behalf of child
        deal(BASE_TOKEN, address(this), collateralAmount);
        IERC20(BASE_TOKEN).approve(AAVE_POOL, collateralAmount);
        IPool(AAVE_POOL).supply(BASE_TOKEN, collateralAmount, address(testShaaveChild), 0);

        /// @dev Expectations
        uint borrowAmount = getBorrowAmount(collateralAmount);
        (uint amountIn, uint amountOut) = swapExactInput(SHORT_TOKEN, BASE_TOKEN, borrowAmount);
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit BorrowSuccess(address(this), SHORT_TOKEN, borrowAmount);
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit SwapSuccess(address(this), SHORT_TOKEN, amountIn, BASE_TOKEN, amountOut);
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit PositionAddedSuccess(address(this), SHORT_TOKEN, borrowAmount);

        /// @dev Act
        bool success = testShaaveChild.short(SHORT_TOKEN, collateralAmount, address(this));
        
        /// @dev Post-action data extraction
        ShaaveChild.PositionData[] memory accountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) = getTokenData(address(testShaaveChild));
        
        /// @dev Assertions
        assert(success);
        // Length
        assertEq(accountingData.length, 1);
        assertEq(accountingData[0].shortTokenAmountsSwapped.length, 1);
        assertEq(accountingData[0].baseAmountsReceived.length, 1);
        assertEq(accountingData[0].collateralAmounts.length, 1);
        assertEq(accountingData[0].baseAmountsSwapped.length, 0);
        assertEq(accountingData[0].shortTokenAmountsReceived.length, 0);

        // Values
        assertEq(accountingData[0].shortTokenAmountsSwapped[0], amountIn);
        assertEq(accountingData[0].baseAmountsReceived[0], amountOut);
        assertEq(accountingData[0].collateralAmounts[0], collateralAmount);
        assertEq(accountingData[0].backingBaseAmount, amountOut);
        assertEq(accountingData[0].shortTokenAddress, SHORT_TOKEN);
        assertEq(accountingData[0].hasDebt, true);

        // Test Aave tokens 
        uint acceptableTolerance = 3;
        int collateralDiff = int(collateralAmount) - int(aTokenBalance);
        uint collateralDiffAbs = collateralDiff < 0 ? uint(-collateralDiff) : uint(collateralDiff);
        int debtDiff = int(amountIn) - int(debtTokenBalance);
        uint debtDiffAbs = debtDiff < 0 ? uint(-debtDiff) : uint(debtDiff);
        assert(collateralDiffAbs <= acceptableTolerance);  // Small tolerance, due to potential interest
        assert(debtDiffAbs <= acceptableTolerance);        // Small tolerance, due to potential interest
        assertEq(baseTokenBalance, amountOut);
        assertEq(userBaseBalance, 0);
    }
}


contract TestChildSellAll is Test, ShaaveChildHelper {

    // Contracts
    ShaaveChild testShaaveChild;

    // Events
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);

    
    function setUp() public {
        // Instantiate Child
        testShaaveChild = new ShaaveChild(address(this), BASE_TOKEN, getAssetDecimals(BASE_TOKEN), getShaaveLTV(BASE_TOKEN));

        // Add short position, so we can sell
        deal(BASE_TOKEN, address(this), TEST_COLLATERAL_AMOUNT);
        IERC20(BASE_TOKEN).approve(AAVE_POOL, TEST_COLLATERAL_AMOUNT);
        IPool(AAVE_POOL).supply(BASE_TOKEN, TEST_COLLATERAL_AMOUNT, address(testShaaveChild), 0);
        bool success = testShaaveChild.short(SHORT_TOKEN, TEST_COLLATERAL_AMOUNT, address(this));
        assert(success);

        // Post short assertions
        ShaaveChild.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
        assertEq(preAccountingData.length, 1);
        assertEq(preAccountingData[0].shortTokenAmountsSwapped.length, 1);
        assertEq(preAccountingData[0].baseAmountsReceived.length, 1);
        assertEq(preAccountingData[0].collateralAmounts.length, 1);
        assertEq(preAccountingData[0].baseAmountsSwapped.length, 0);
        assertEq(preAccountingData[0].shortTokenAmountsReceived.length, 0);
    }

    function test_reduecePosition_all_single() public {
        /// @dev Pre-action data extraction
        ShaaveChild.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();

        /// @dev Expectations
        uint baseTokenConversion = 10 ** (18 - getAssetDecimals(BASE_TOKEN));
        (uint amountIn, uint amountOut) = swapToShortToken(SHORT_TOKEN, BASE_TOKEN, preAccountingData[0].shortTokenAmountsSwapped[0], preAccountingData[0].backingBaseAmount, baseTokenConversion);
        vm.expectEmit(true, true, true, true, address(testShaaveChild));
        emit SwapSuccess(address(this), BASE_TOKEN, amountIn, SHORT_TOKEN, amountOut);

        /// @dev Act
        vm.warp(block.timestamp + 120);    // Trick Aave into thinking it's not a flash loan ;)
        bool success = testShaaveChild.reducePosition(SHORT_TOKEN, 100, true);

        /// @dev Post-action data extraction
        ShaaveChild.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) = getTokenData(address(testShaaveChild));

        /// @dev Assertions
        assert(success);
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
        ShaaveChild.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();

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
        ShaaveChild.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) = getTokenData(address(testShaaveChild));

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
        ShaaveChild.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
    
        /// @dev Expectations
        uint neededAmountOut = preAccountingData[0].shortTokenAmountsSwapped[0] / UNISWAP_AMOUNT_OUT_LOSSES_FACTOR;
        uint borrowAmount = getBorrowAmount(TEST_COLLATERAL_AMOUNT);
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
        ShaaveChild.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, uint baseTokenBalance, uint userBaseBalance) = getTokenData(address(testShaaveChild));

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


    function test_fail_reduecePosition_amount(uint percentageReduction) public {
        vm.assume(percentageReduction > 100);

        /// @dev Expectations
        vm.expectRevert("Invalid percentage.");

        /// @dev Act
        testShaaveChild.reducePosition(SHORT_TOKEN, percentageReduction, true);
    }
}

contract TestChildSellSome is Test, ShaaveChildHelper {

    // Contracts
    ShaaveChild testShaaveChild;

    // Events
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);

    function setUp() public {
        // Instantiate Child
        testShaaveChild = new ShaaveChild(address(this), BASE_TOKEN, getAssetDecimals(BASE_TOKEN), getShaaveLTV(BASE_TOKEN));

        // Add short position, so we can sell
        deal(BASE_TOKEN, address(this), TEST_COLLATERAL_AMOUNT);
        IERC20(BASE_TOKEN).approve(AAVE_POOL, TEST_COLLATERAL_AMOUNT);
        IPool(AAVE_POOL).supply(BASE_TOKEN, TEST_COLLATERAL_AMOUNT, address(testShaaveChild), 0);
        assert(testShaaveChild.short(SHORT_TOKEN, TEST_COLLATERAL_AMOUNT, address(this)));

        // Post short assertions
        ShaaveChild.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
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
        ShaaveChild.PositionData[] memory preAccountingData = testShaaveChild.getAccountingData();
        (uint pre_aTokenBalance, uint pre_debtTokenBalance, , ) = getTokenData(address(testShaaveChild));

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
        ShaaveChild.PositionData[] memory postAccountingData = testShaaveChild.getAccountingData();
        (uint aTokenBalance, uint debtTokenBalance, , ) = getTokenData(address(testShaaveChild));
        

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
