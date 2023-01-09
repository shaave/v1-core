// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Foundry
import "forge-std/Test.sol";

// External packages
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";
import "@aave-protocol/interfaces/IPool.sol";

// Local file imports
import "../../src/libraries/PricingLib.sol";
import "../../src/interfaces/IERC20Metadata.sol";
import "./UniswapUtils.t.sol";
import "./Constants.t.sol";

contract ChildUtils is UniswapUtils {
    using PricingLib for address;
    using MathLib for uint256;

    function getShaaveLTV(address _baseToken) internal view returns (uint256) {
        uint256 bitMap = IPool(AAVE_POOL).getReserveData(_baseToken).configuration.data;
        uint256 aaveLTV = (bitMap & ((1 << 16) - 1)) / 100; // bit 0-15: LTV
        return aaveLTV - LTV_BUFFER;
    }

    function getBorrowAmount(uint256 _testCollateralAmount, address _baseToken) internal view returns (uint256) {
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
