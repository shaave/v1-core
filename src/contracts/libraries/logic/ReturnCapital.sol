// contracts/ReturnCapital.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;


// Local Imports
import "./ShaavePricing.sol";

// External Package Imports
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@aave-protocol/interfaces/IPool.sol";


/**
 * @title ReturnCapital library
 * @author Shaave
 * @dev Implements the logic related to reducing a short position.
*/
library ReturnCapital {

    address constant aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;   // Goerli Aave Pool Address

    /** 
    * @dev This function is used to calculate a trade's gains.
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _baseTokenAddress The address of the base token.
    * @param _totalShortTokenDebt The contract's total debt for a specific short token.
    * @param _percentageReduction The percentage reduction of the user's short position; 100% constitutes closing out the position.
    * @param _positionbackingBaseAmount The total amount of base token backing an individual asset short position.
    * @return gains The gains the trade at hand yielded; this value will be paid out to the user.
    * @notice debtValueBase This total debt's value in the base asset (collateral asset), for a specific asset.
    * @notice positionbackingBaseAmount The amount of base (collateral) asset this contract has allocated for a specific asset short position.
    **/
    function calculatePositionGains(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _totalShortTokenDebt,
        uint _percentageReduction,
        uint _positionbackingBaseAmount
    ) internal view returns (uint gains) {

        uint priceOfShortTokenInBase = ShaavePricing.getAssetPriceInBase(_baseTokenAddress, _shortTokenAddress);
        uint debtValueBase = (priceOfShortTokenInBase * _totalShortTokenDebt) / 1e18; // TODO: Test calculation

        if (_positionbackingBaseAmount > debtValueBase) {
            gains = (_percentageReduction * (_positionbackingBaseAmount - debtValueBase)) / 100; // Works in Remix
        } else {
            gains = 0;
        }
    }

    /** 
    * @dev This function is used to calculate the amount of collateral that can be withdrawn at any given sell event.
    *      It's structured to always withdraw the maximum amount of collateral, such that the ratio of total debt to 
    *      total collateral remains below 70%.
    * @param _user The address of the user that's attempting to withdraw collateral.
    * @return withdrawalAmount The gains the trade at hand yielded; this value will be paid out to the user.
    * @notice totalDebtBase is the value of debt, in the base (collateral) token across all borrowed assets.
    **/
    function calculateCollateralWithdrawAmount(address _user) internal view returns (uint withdrawalAmount) {
        
        (uint totalCollateralBase, uint totalDebtBase, , , , ) = IPool(aavePoolAddress).getUserAccountData(_user);

        int maxWithdrawal = totalCollateralBase - (totalDebtBase / 0.70);  //FIXME: may need to scale here TODO: Ain't gonna work

        if (maxWithdrawal > 0) {
            withdrawalAmount = maxWithdrawal;
        } else {
            withdrawalAmount = 0;
        }
    }

    
}