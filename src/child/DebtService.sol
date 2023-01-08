// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// External Package Imports
import "solmate/utils/SafeTransferLib.sol";
import "@aave-protocol/interfaces/IPool.sol";

// Local imports
import "../interfaces/IERC20Metadata.sol";
import "../libraries/ShaavePricing.sol";
import "../libraries/Math.sol";
import "../libraries/ReturnCapital.sol";

abstract contract DebtService {
    using ShaavePricing for address;
    using Math for uint256;

    // Constants
    address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public constant AAVE_ORACLE = 0xb023e699F5a33916Ea823A16485e259257cA8Bd1;

    // Immutables
    uint256 public immutable shaaveLTV;
    uint256 public immutable baseTokenConversion; // To Wei
    address public immutable baseToken;
    address public immutable user;

    // Events
    event BorrowSuccess(address user, address borrowTokenAddress, uint256 amount);

    constructor(address _user, address _baseToken, uint256 _baseTokenDecimals, uint256 _shaaveLTV) {
        baseToken = _baseToken;
        baseTokenConversion = 10 ** (18 - _baseTokenDecimals);
        shaaveLTV = _shaaveLTV;
        user = _user;
    }

    function borrowAsset(address _shortToken, address _user, uint256 _baseTokenAmount)
        internal
        returns (uint256 borrowAmount)
    {
        SafeTransferLib.safeApprove(ERC20(baseToken), AAVE_POOL, _baseTokenAmount);
        IPool(AAVE_POOL).supply(baseToken, _baseTokenAmount, address(this), 0);

        // Calculate the amount that can be borrowed
        uint256 shortTokenConversion = (10 ** (18 - IERC20Metadata(_shortToken).decimals()));
        uint256 priceOfShortTokenInBase = _shortToken.pricedIn(baseToken); // Wei
        borrowAmount = ((_baseTokenAmount * baseTokenConversion * shaaveLTV) / 100).dividedBy(
            priceOfShortTokenInBase, 18
        ) / shortTokenConversion;

        // Since parent supplied collateral on this contract's behalf, borrow asset
        IPool(AAVE_POOL).borrow(_shortToken, borrowAmount, 2, 0, address(this));
        emit BorrowSuccess(_user, _shortToken, borrowAmount);
    }

    function repayAsset(address _shortToken, uint256 _amount) internal {
        // Repay Aave loan with the amount of short token received from Uniswap
        SafeTransferLib.safeApprove(ERC20(_shortToken), AAVE_POOL, _amount);
        IPool(AAVE_POOL).repay(_shortToken, _amount, 2, address(this));
    }

    function withdraw(uint256 _amount) internal {
        IPool(AAVE_POOL).withdraw(baseToken, _amount, user);
    }

    /**
     * @dev Returns this contract's total debt for a given short token (principle + interest).
     * @param _shortToken The address of the token the user has shorted.
     * @return outstandingDebt This contract's total debt for a given short token, in whatever decimals that short token has.
     *
     */
    function getOutstandingDebt(address _shortToken) public view userOnly returns (uint256 outstandingDebt) {
        address variableDebtTokenAddress = IPool(AAVE_POOL).getReserveData(_shortToken).variableDebtTokenAddress;
        outstandingDebt = IERC20(variableDebtTokenAddress).balanceOf(address(this));
    }

    /**
     * @dev  This function returns a list of data related to the Aave account that this contract has.
     * @return totalCollateralBase The value of all supplied collateral, in base token.
     * @return totalDebtBase The value of all debt, in base token.
     * @return availableBorrowBase The amount, in base token, that can still be borrowed.
     * @return currentLiquidationThreshold Aave's liquidation threshold.
     * @return ltv The (Aave) account-wide loan-to-value ratio.
     * @return healthFactor Aave's account-wide health factor.
     * @return maxWithdrawalAmount The maximum amount of collateral a user can withdraw, given Shaave's LTV.
     *
     */
    function getAaveAccountData()
        public
        view
        userOnly
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor,
            uint256 maxWithdrawalAmount
        )
    {
        maxWithdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);
        (totalCollateralBase, totalDebtBase, availableBorrowBase, currentLiquidationThreshold, ltv, healthFactor) =
            IPool(AAVE_POOL).getUserAccountData(address(this)); // Must multiply by 1e10 to get Wei
    }

    /**
     * @dev  This function returns the this contract's total debt, in terms of the base token (in Wei), for a given short token.
     * @param _shortToken The address of the token the user has shorted.
     * @return outstandingDebtBase This contract's total debt, in terms the base token (in Wei), for a given short token.
     *
     */
    function getOutstandingDebtBase(address _shortToken) public view userOnly returns (uint256 outstandingDebtBase) {
        uint256 priceOfShortTokenInBase = _shortToken.pricedIn(baseToken); // Wei
        uint256 totalShortTokenDebt = getOutstandingDebt(_shortToken); // Wei
        outstandingDebtBase = (priceOfShortTokenInBase * totalShortTokenDebt).dividedBy(1e18, 0); // Wei
    }

    modifier userOnly() {
        require(msg.sender == user, "Unauthorized.");
        _;
    }
}
