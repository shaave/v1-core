// contracts/libraries/ReturnCapital.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Local Imports
import "./ShaavePricing.sol";
import "./Math.sol";

// External Package Imports
import "@aave-protocol/interfaces/IPool.sol";

import "forge-std/console.sol";

/**
 * @title ReturnCapital library
 * @author shAave
 * @dev Implements the logic related to reducing a short position.
 */
library ReturnCapital {
    using Math for uint256;
    using ShaavePricing for address;

    address constant aavePoolAddress = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    uint256 constant WITHDRAWAL_BUFFER = 1e15; // TODO: cut this in half?

    /**
     * @dev This function is used to calculate a trade's gains (in Wei).
     * @param _shortToken The address of the short token the user wants to reduce his or her position in.
     * @param _baseTokenAddress The address of the base token.
     * @param _totalShortTokenDebt The contract's total debt for a specific short token (Units: 18 decimals).
     * @param _percentageReduction The percentage reduction of the user's short position; 100 constitutes closing out the position.
     * @param _positionbackingBaseAmount The amount of base token backing a position (Units: 18 decimals).
     * @return gains The gains the trade at hand yielded; if nonzero, this value (in Wei) will be paid out to the user.
     * @notice debtValueBase This total debt's value in the base asset (Units: base token decimals).
     *
     */
    function getPositionGains(
        address _shortToken,
        address _baseTokenAddress,
        uint256 _percentageReduction,
        uint256 _positionbackingBaseAmount,
        uint256 _totalShortTokenDebt
    ) internal view returns (uint256 gains) {
        uint256 priceOfShortTokenInBase = _shortToken.pricedIn(_baseTokenAddress); // Wei
        uint256 debtValueBase = (priceOfShortTokenInBase * _totalShortTokenDebt) / 1e18; // Wei
        if (_positionbackingBaseAmount > debtValueBase) {
            gains = (_percentageReduction * (_positionbackingBaseAmount - debtValueBase)) / 100; // Wei
        } else {
            gains = 0;
        }
    }

    /**
     * @dev This function is used to calculate the amount of collateral (in Wei) that can be withdrawn at any given sell event.
     * It's structured to always withdraw the maximum amount of collateral from Aave with a 10% buffer (to prevent damaging
     * the child contract's health factor on Aave), such that the debt-to-collateral ratio remains below 70% (Aave's max
     * is 80% for USDC).
     * @param _childAddress The address of the contract that's attempting to withdraw collateral.
     * @return withdrawalAmount The amount of collateral (in Wei) to be withdrawn to the user.
     * @notice totalCollateralBase The total collateral supplied on the child contract's behalf (must multiply by 1e10 to get Wei)
     * @notice totalDebtBase The total debt value, as measured in base tokens, across all borrowed assets (must multiply by 1e10 to get Wei)
     * @notice maxWithdrawal The maximum amount of collateral (in Wei) that can be withdrawn without the debt-to-collateral ratio
     * becoming greater than 70%. Since Aave's getUserAccountData() returns totalCollateralBase and
     * totalDebtBase as (Ether * 1e8) units, it's possible for debt smaller than 1e10 Wei to exist,
     * which would cause the contract to attempt to widthraw more collateral than Aave allows. Since,
     * this would cause a transaction reversion, we must leave enough collateral to back any uncaptured
     * debt (smaller than 1e10 Wei).
     *
     */
    function getMaxWithdrawal(address _childAddress, uint256 _shaaveLTV)
        internal
        view
        returns (uint256 withdrawalAmount)
    {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) =
            IPool(aavePoolAddress).getUserAccountData(_childAddress); // Multiply by 1e10 to get Wei

        uint256 loanBackingCollateral = ((totalDebtBase / _shaaveLTV) * 100); // Wei

        console.log("loanBackingCollateral:", loanBackingCollateral);

        if (totalCollateralBase > loanBackingCollateral) {
            withdrawalAmount = ((totalCollateralBase - loanBackingCollateral) * 1e10) - WITHDRAWAL_BUFFER; // Wei
        } else {
            withdrawalAmount = 0; // Wei
        }

        console.log("withdrawalAmount:", withdrawalAmount);
        console.log("totalCollateralBase:", totalCollateralBase);
        console.log("totalDebtBase:", totalDebtBase);
    }
}
