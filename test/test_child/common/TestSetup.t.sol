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
import "../../../src/libraries/ShaavePricing.sol";
import "../../../src/interfaces/IERC20Metadata.sol";
import "../../common/constants.t.sol";

contract UniswapHelper is Test {
    using ShaavePricing for address;

    /// @dev This is a test function for computing expected results
    function swapExactInput(address _inputToken, address _outputToken, uint256 _tokenInAmount)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        deal(SHORT_TOKEN, address(this), _tokenInAmount);

        ISwapRouter SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _tokenInAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
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
        uint256 _outputTokenAmount,
        uint256 _inputMax,
        uint256 baseTokenConversion
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        // Give this contract (positionBackingBaseAmount) base tokens
        deal(BASE_TOKEN, address(this), _inputMax);

        ISwapRouter SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _inputMax);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _inputToken,
            tokenOut: _outputToken,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _outputTokenAmount,
            amountInMaximum: _inputMax,
            sqrtPriceLimitX96: 0
        });

        try SWAP_ROUTER.exactOutputSingle(params) returns (uint256 returnedAmountIn) {
            (amountIn, amountOut) = (returnedAmountIn, _outputTokenAmount);
        } catch {
            amountIn = getAmountIn(_outputTokenAmount, _outputToken, _inputMax, baseTokenConversion);
            (amountIn, amountOut) = swapExactInput(_inputToken, _outputToken, amountIn);
        }

        // Revert to previous snapshot, as if swap never happend
        vm.revertTo(id);
    }

    /// @dev This is a test function for computing expected results
    function getAmountIn(
        uint256 _positionReduction,
        address _shortToken,
        uint256 _backingBaseAmount,
        uint256 baseTokenConversion
    ) internal view returns (uint256) {
        /// @dev Units: baseToken decimals
        uint256 priceOfShortTokenInBase = _shortToken.pricedIn(BASE_TOKEN) / baseTokenConversion;

        /// @dev Units: baseToken decimals = (baseToken decimals * shortToken decimals) / shortToken decimals
        uint256 positionReductionBase =
            (priceOfShortTokenInBase * _positionReduction) / (10 ** IERC20Metadata(_shortToken).decimals());

        if (positionReductionBase <= _backingBaseAmount) {
            return positionReductionBase;
        } else {
            return _backingBaseAmount;
        }
    }
}

contract ShaaveChildHelper is UniswapHelper {
    using ShaavePricing for address;
    using Math for uint256;

    // Variables
    uint256 public constant LTV_BUFFER = 10;

    function getShaaveLTV(address _baseToken) internal view returns (uint256) {
        uint256 bitMap = IPool(AAVE_POOL).getReserveData(_baseToken).configuration.data;
        uint256 aaveLTV = (bitMap & ((1 << 16) - 1)) / 100; // bit 0-15: LTV
        return aaveLTV - LTV_BUFFER;
    }

    function getBorrowAmount(uint256 _testCollateralAmount, address _baseToken) internal view returns (uint256) {
        console.log("test Collateral amount:", _testCollateralAmount);
        uint256 baseTokenConversion = 10 ** (18 - IERC20Metadata(_baseToken).decimals());
        uint256 shortTokenConversion = 10 ** (18 - IERC20Metadata(SHORT_TOKEN).decimals());
        uint256 priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(_baseToken);
        uint256 shaaveLTV = getShaaveLTV(_baseToken);
        return ((_testCollateralAmount * baseTokenConversion * shaaveLTV) / 100).dividedBy(priceOfShortTokenInBase, 18)
            .dividedBy(shortTokenConversion, 0);
    }

    function getOutstandingDebt(address _shortToken, address _testShaaveChild) internal view returns (uint256) {
        address variableDebtTokenAddress = IPool(AAVE_POOL).getReserveData(_shortToken).variableDebtTokenAddress;
        return IERC20(variableDebtTokenAddress).balanceOf(_testShaaveChild);
    }

    function getTokenData(address _child, address _baseToken)
        internal
        view
        returns (uint256 aTokenBalance, uint256 debtTokenBalance, uint256 baseTokenBalance, uint256 userBaseBalance)
    {
        address baseAToken = IPool(AAVE_POOL).getReserveData(_baseToken).aTokenAddress;
        address shortDebtToken = IPool(AAVE_POOL).getReserveData(SHORT_TOKEN).variableDebtTokenAddress;
        aTokenBalance = IERC20(baseAToken).balanceOf(_child);
        debtTokenBalance = IERC20(shortDebtToken).balanceOf(_child);
        baseTokenBalance = IERC20(_baseToken).balanceOf(_child);
        userBaseBalance = IERC20(_baseToken).balanceOf(address(this));
    }

    function getGains(
        uint256 _backingBaseAmount,
        uint256 _amountIn,
        uint256 _baseTokenConversion,
        uint256 _percentageReduction,
        address _testShaaveChild
    ) internal view returns (uint256 gains) {
        uint256 debtAfterRepay =
            getOutstandingDebt(SHORT_TOKEN, _testShaaveChild) * (10 ** (18 - IERC20Metadata(SHORT_TOKEN).decimals())); // Wei
        uint256 backingBaseAmountWei = (_backingBaseAmount - _amountIn) * _baseTokenConversion;

        uint256 priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN); // Wei
        uint256 debtValueBase = (priceOfShortTokenInBase * debtAfterRepay) / 1e18; // Wei
        if (backingBaseAmountWei > debtValueBase) {
            gains = (_percentageReduction * (backingBaseAmountWei - debtValueBase)) / 100; // Wei
        } else {
            gains = 0;
        }
    }

    function getWithdrawal(address _testShaaveChild, uint256 amountOut) internal returns (uint256 withdrawalAmount) {
        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        deal(SHORT_TOKEN, address(this), amountOut);
        vm.warp(block.timestamp + 120); // Trick Aave into thinking it's not a flash loan ;)
        IERC20(SHORT_TOKEN).approve(AAVE_POOL, amountOut);
        IPool(AAVE_POOL).repay(SHORT_TOKEN, amountOut, 2, _testShaaveChild);

        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = IPool(AAVE_POOL).getUserAccountData(_testShaaveChild); // Units: 8 decimals

        uint256 loanBackingCollateral = ((totalDebtBase / getShaaveLTV(BASE_TOKEN)) * 100); // Wei

        if (totalCollateralBase > loanBackingCollateral) {
            withdrawalAmount = ((totalCollateralBase - loanBackingCollateral) * 1e10) - WITHDRAWAL_BUFFER; // Wei
        } else {
            withdrawalAmount = 0;
        }

        // Revert to previous snapshot, as if repay never happened
        vm.revertTo(id);
    }
}
