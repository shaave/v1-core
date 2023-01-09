// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/libraries/CapitalLib.sol";
import "../../src/libraries/PricingLib.sol";
import "../../src/libraries/MathLib.sol";
import "../../src/child/Child.sol";
import "../../src/interfaces/IERC20Metadata.sol";
import "../common/Constants.t.sol";

// External package imports
import "@aave-protocol/interfaces/IAaveOracle.sol";
import "@aave-protocol/interfaces/IPool.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

contract ReturnCapitalHelper {
    function getShaaveLTV(address baseToken) internal view returns (int256) {
        uint256 bitMap = IPool(AAVE_POOL).getReserveData(baseToken).configuration.data;
        uint256 lastNbits = 16; // bit 0-15: LTV
        uint256 mask = (1 << lastNbits) - 1;
        uint256 aaveLTV = (bitMap & mask) / 100;
        return int256(aaveLTV) - int256(LTV_BUFFER);
    }
}

contract GainsTest is Test, ReturnCapitalHelper {
    using MathLib for uint256;
    using PricingLib for address;

    uint256 constant FULL_REDUCTION = 100;
    uint256 constant TEST_SHORT_TOKEN_DEBT = 100e18; // 100 tokens

    function test_getPositionGains_noGains(uint256 valueLost) public {
        // Setup
        uint256 priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN); // Wei
        uint256 debtValueInBase = (priceOfShortTokenInBase * TEST_SHORT_TOKEN_DEBT) / 1e18; // Wei
        vm.assume(valueLost <= debtValueInBase);
        uint256 positionBackingBaseAmount = debtValueInBase - valueLost;

        // Act
        uint256 gains = CapitalLib.getPositionGains(
            SHORT_TOKEN, BASE_TOKEN, FULL_REDUCTION, positionBackingBaseAmount, TEST_SHORT_TOKEN_DEBT
        );

        // Assertions
        assertEq(gains, 0);
    }

    function test_getPositionGains_gains(uint256 valueAccrued) public {
        vm.assume(valueAccrued < 1e9);
        // Setup
        uint256 priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN); // Wei
        uint256 debtValueInBase = (priceOfShortTokenInBase * TEST_SHORT_TOKEN_DEBT) / 1e18; // Wei
        uint256 positionBackingBaseAmount = debtValueInBase + valueAccrued;

        // Act
        uint256 gains = CapitalLib.getPositionGains(
            SHORT_TOKEN, BASE_TOKEN, FULL_REDUCTION, positionBackingBaseAmount, TEST_SHORT_TOKEN_DEBT
        );

        // Assertions
        assertEq(gains, valueAccrued);
    }
}

contract WithdrawalHelper is Test {
    using MathLib for uint256;
    using PricingLib for address;

    function calculateMaxWithdrawal(address testChild, uint256 shaaveLTV)
        internal
        view
        returns (uint256 withdrawalAmount)
    {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = IPool(AAVE_POOL).getUserAccountData(testChild);
        uint256 loanBackingCollateral = (totalDebtBase.dividedBy(shaaveLTV, 0) * 100) * 1e10;

        if (totalCollateralBase * 1e10 > loanBackingCollateral) {
            withdrawalAmount =
                ((totalCollateralBase - (totalDebtBase.dividedBy(shaaveLTV, 0) * 100)) * 1e10) - WITHDRAWAL_BUFFER;
        } else {
            withdrawalAmount = 0; // Wei
        }
    }

    function getBorrowAmount(address baseToken, uint256 baseTokenAmount, uint256 shaaveLTV, uint256 baseTokenConversion)
        internal
        view
        returns (uint256)
    {
        uint256 shortTokenConversion = (10 ** (18 - IERC20Metadata(SHORT_TOKEN).decimals()));
        uint256 priceOfShortTokenInBase = SHORT_TOKEN.pricedIn(baseToken); // Wei
        return ((baseTokenAmount * baseTokenConversion * shaaveLTV) / 100).dividedBy(priceOfShortTokenInBase, 18)
            / shortTokenConversion;
    }
}

contract WithdrawalTest is Test, ReturnCapitalHelper, WithdrawalHelper, TestUtils {
    using AddressLib for address[];

    Child[] children;
    uint256[] shaaveLTVs;

    function setUp() public {
        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        for (uint256 i; i < reserves.length; i++) {
            if (!BANNED_COLLATERAL.includes(reserves[i])) {
                uint8 assetDecimals = IERC20Metadata(reserves[i]).decimals();
                uint256 shaaveLTV = uint256(getShaaveLTV(reserves[i]));
                if (shaaveLTV > 0) {
                    shaaveLTVs.push(shaaveLTV);
                    children.push(new Child(address(this), reserves[i], assetDecimals, shaaveLTV));
                }
            }
        }
    }

    function test_getMaxWithdrawal_zeroWithdrawal() public {
        // Act
        uint256 withdrawalAmount = CapitalLib.getMaxWithdrawal(CHILD_ADDRESS, uint256(getShaaveLTV(BASE_TOKEN)));

        // Assertions
        assertEq(withdrawalAmount, 0);
    }

    function test_getMaxWithdrawal_nonZeroWithdrawal() public {
        // Setup

        for (uint256 i; i < children.length; i++) {
            uint256 testBaseAmount = 1e18 / children[i].baseTokenConversion();

            vm.startPrank(address(children[i]));
            // Supply
            deal(children[i].baseToken(), address(children[i]), testBaseAmount);
            TransferHelper.safeApprove(children[i].baseToken(), AAVE_POOL, testBaseAmount);
            IPool(AAVE_POOL).supply(children[i].baseToken(), testBaseAmount, address(children[i]), 0);

            // Borrow
            uint256 borrowAmount = getBorrowAmount(
                children[i].baseToken(), testBaseAmount, shaaveLTVs[i], children[i].baseTokenConversion()
            ) / 2;
            IPool(AAVE_POOL).borrow(SHORT_TOKEN, borrowAmount, 2, 0, address(children[i]));

            /// @dev Expectations
            uint256 expectedMaxWithdrawal = calculateMaxWithdrawal(address(children[i]), shaaveLTVs[i]);

            // Act
            uint256 actualWithdrawalAmount = CapitalLib.getMaxWithdrawal(address(children[i]), shaaveLTVs[i]);

            // Assertions
            assertEq(actualWithdrawalAmount, expectedMaxWithdrawal);

            vm.stopPrank();
        }
    }
}
