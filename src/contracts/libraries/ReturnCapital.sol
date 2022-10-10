// contracts/libraries/ReturnCapital.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;


// Local Imports
import "./ShaavePricing.sol";
import "./Math.sol";

// External Package Imports
import "@aave-protocol/interfaces/IPool.sol";


/**
 * @title ReturnCapital library
 * @author shAave
 * @dev Implements the logic related to reducing a short position.
*/
library ReturnCapital {

    using Math for uint;
    using ShaavePricing for address;

    address constant aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;   // Goerli Aave Pool Address

    /** 
    * @dev This function is used to calculate a trade's gains (in Wei).
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _baseTokenAddress The address of the base token.
    * @param _totalShortTokenDebt The contract's total debt (in Wei) for a specific short token.
    * @param _percentageReduction The percentage reduction of the user's short position; 100% constitutes closing out the position.
    * @param _positionbackingBaseAmount The amount of base asset (in Wei) this contract has allocated for a specific asset short position.
    * @return gains The gains the trade at hand yielded; if nonzero, this value (in Wei) will be paid out to the user.
    * @notice debtValueBase This total debt's value in the base asset (in Wei).
    **/
    function calculatePositionGains(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _percentageReduction,
        uint _positionbackingBaseAmount,
        uint _totalShortTokenDebt
    ) internal view returns (uint gains) {
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(_baseTokenAddress);                          // Wei
        uint debtValueBase = (priceOfShortTokenInBase * _totalShortTokenDebt).dividedBy(1e18, 0);               // Wei
        if (_positionbackingBaseAmount > debtValueBase) {
            gains = (_percentageReduction * (_positionbackingBaseAmount - debtValueBase)).dividedBy(100, 0);    // Wei
        } else {
            gains = 0;
        }
    }

    /** 
    * @dev This function is used to calculate the amount of collateral (in Wei) that can be withdrawn at any given sell event.
    *      It's structured to always withdraw the maximum amount of collateral from Aave with a 10% buffer (to prevent damaging
    *      the child contract's health factor on Aaave), such that the debt-to-collateral ratio remains below 70% (Aave's max 
    *      is 80% for USDC).
    * @param _childAddress The address of the contract that's attempting to withdraw collateral.
    * @return withdrawalAmount The amount of collateral (in Wei) to be withdrawn to the user.
    * @notice totalCollateralBase The total collateral supplied on the child contract's behalf (must multiply by 1e10 to get Wei)
    * @notice totalDebtBase The total debt value, as measured in base tokens, across all borrowed assets (must multiply by 1e10 to get Wei)
    * @notice maxWithdrawal The maximum amount of collateral (in Wei) that can be withdrawn without the debt-to-collateral ratio
    *                       becoming greater than 70%. Since Aave's getUserAccountData() returns totalCollateralBase and
    *                       totalDebtBase as (Ether * 1e8) units, it's possible for debt smaller than 1e10 Wei to exist,
    *                       which would cause the contract to attempt to widthraw more collateral than Aave allows. Since,
    *                       this would cause a transaction reversion, we must leave enough collateral to back any uncaptured
    *                       debt (smaller than 1e10 Wei). 
    **/
    function calculateCollateralWithdrawAmount(address _childAddress) internal view returns (uint withdrawalAmount) {
        uint ShaaveDebtToCollateral = 70;
        uint maxUncapturedDebt      = 9999999999;
        uint uncapturedCollateral   = (maxUncapturedDebt.dividedBy(ShaaveDebtToCollateral,0) * 100);                         // Wei
        uint maxWithdrawal;

        (uint totalCollateralBase, uint totalDebtBase, , , , ) = IPool(aavePoolAddress).getUserAccountData(_childAddress);   // Must multiply by 1e10 to get Wei

        if (totalCollateralBase > (uncapturedCollateral.dividedBy(1e10, 0) + (totalDebtBase.dividedBy(ShaaveDebtToCollateral, 0) * 100))){
            maxWithdrawal    = ((totalCollateralBase - (totalDebtBase.dividedBy(ShaaveDebtToCollateral, 0) * 100)) * 1e10) - uncapturedCollateral;    // Wei
            withdrawalAmount = maxWithdrawal;
        } else {
            withdrawalAmount = 0;
        }

        return withdrawalAmount;
    }   
}