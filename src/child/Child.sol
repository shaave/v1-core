// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Local Imports
import "./SwapService.sol";
import "./DebtService.sol";
import "../libraries/ShaavePricing.sol";
import "../libraries/ReturnCapital.sol";
import "../libraries/AddressArray.sol";
import "../interfaces/IERC20Metadata.sol";

// External Package Imports
import "solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "forge-std/console.sol";

/// @title shAave child contract, owned by the Parent
contract Child is SwapService, DebtService, Ownable {
    using AddressArray for address[];
    using ShaavePricing for address;
    using Math for uint256;

    // Child Variables
    struct PositionData {
        // -- Arrays related to adding to a position --
        uint256[] shortTokenAmountsSwapped;
        uint256[] baseAmountsReceived;
        uint256[] collateralAmounts;
        // -- Arrays related to reducing a position --
        uint256[] baseAmountsSwapped;
        uint256[] shortTokenAmountsReceived;
        // -- Miscellaneous --
        uint256 backingBaseAmount;
        address shortTokenAddress;
        bool hasDebt;
    }

    mapping(address => address) private userContracts;
    address[] private openedShortPositions;
    mapping(address => PositionData) public userPositions;

    // Events
    event PositionAddedSuccess(address user, address shortTokenAddress, uint256 amount);

    constructor(address _user, address _baseToken, uint256 _baseTokenDecimals, uint256 _shaaveLTV)
        DebtService(_user, _baseToken, _baseTokenDecimals, _shaaveLTV)
    {}

    /**
     * @dev This function is used to short an asset; it's exclusively called by ShaavePerent.addShortPosition().
     * @param _shortToken The address of the short token the user wants to reduce his or her position in.
     * @param _baseTokenAmount The amount of collateral (in WEI) that will be used for adding to a short position.
     * @notice currentAssetPrice is the current price of the short token, in terms of the collateral token.
     * @notice borrowAmount is the amount of the short token that will be borrowed from Aave.
     *
     */
    function short(address _shortToken, uint256 _baseTokenAmount, address _user) public onlyOwner returns (bool) {
        console.log("we got to short.");

        // Borrow asset
        uint256 borrowAmount = borrowAsset(_shortToken, _user, _baseTokenAmount);

        // Swap borrowed asset for base token
        (uint256 amountIn, uint256 amountOut) = swapExactInput(_shortToken, baseToken, borrowAmount);
        emit PositionAddedSuccess(_user, _shortToken, borrowAmount);

        // Update user's accounting
        if (userPositions[_shortToken].shortTokenAddress == address(0)) {
            userPositions[_shortToken].shortTokenAddress = _shortToken;
        }

        if (!userPositions[_shortToken].hasDebt) {
            userPositions[_shortToken].hasDebt = true;
        }

        if (!openedShortPositions.includes(_shortToken)) {
            openedShortPositions.push(_shortToken);
        }

        userPositions[_shortToken].shortTokenAmountsSwapped.push(amountIn);
        userPositions[_shortToken].baseAmountsReceived.push(amountOut);
        userPositions[_shortToken].collateralAmounts.push(_baseTokenAmount);
        userPositions[_shortToken].backingBaseAmount += amountOut;

        return true;
    }

    /**
     * @dev This function is used to reduce a short position.
     * @param _shortToken The address of the short token the user wants to reduce his or her position in.
     * @param _percentageReduction The percentage reduction of the user's short position; 100% constitutes closing out the position
     * @param _withdrawCollateral A boolean to withdraw collateral or not.
     * @notice positionReduction The amount of short token that the position is being reduced by.
     * @notice totalShortTokenDebt The total amount that this contract owes Aave (principle + interest).
     *
     */
    function reducePosition(address _shortToken, uint256 _percentageReduction, bool _withdrawCollateral)
        public
        userOnly
        returns (bool)
    {
        require(_percentageReduction > 0 && _percentageReduction <= 100, "Invalid percentage.");

        // Calculate the amount of short tokens the short position will be reduced by
        uint256 positionReduction = (getOutstandingDebt(_shortToken) * _percentageReduction) / 100; // Uints: short token decimals

        // Swap short tokens for base tokens
        (uint256 amountIn, uint256 amountOut) = swapToShortToken(
            _shortToken, baseToken, positionReduction, userPositions[_shortToken].backingBaseAmount, baseTokenConversion
        );

        // Repay Aave loan with the amount of short token received from Uniswap
        repayAsset(_shortToken, amountOut);

        /// @dev shortTokenConversion = (10 ** (18 - IERC20Metadata(_shortToken).decimals()))
        uint256 debtAfterRepay = getOutstandingDebt(_shortToken) * (10 ** (18 - IERC20Metadata(_shortToken).decimals())); // Wei, as that's what getPositionGains wants

        // Withdraw correct percentage of collateral, and return to user
        if (_withdrawCollateral) {
            uint256 withdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);

            if (withdrawalAmount > 0) {
                withdraw(withdrawalAmount / baseTokenConversion);
            }
        }

        // If trade was profitable, pay user gains
        uint256 backingBaseAmountWei = (userPositions[_shortToken].backingBaseAmount - amountIn) * baseTokenConversion;
        uint256 gains = ReturnCapital.getPositionGains(
            _shortToken, baseToken, _percentageReduction, backingBaseAmountWei, debtAfterRepay
        );
        if (gains > 0) {
            SafeTransferLib.safeTransfer(ERC20(baseToken), msg.sender, gains / baseTokenConversion);
        }

        // Update child contract's accounting
        userPositions[_shortToken].baseAmountsSwapped.push(amountIn);
        userPositions[_shortToken].shortTokenAmountsReceived.push(amountOut);
        userPositions[_shortToken].backingBaseAmount -= (amountIn + gains / baseTokenConversion);

        if (debtAfterRepay == 0) {
            userPositions[_shortToken].hasDebt = false;
        }

        return true;
    }

    /**
     * @dev  This function repays all child's outstanding (per asset) debt, in the case where all base token has been used already.
     * @param _shortToken The address of the token the user has shorted.
     * @param _paymentToken The address of the token used to repay outstanding debt (either base token or short token).
     * @param _paymentAmount The amount that's sent to repay the outstanding debt.
     * @param _withdrawCollateral A boolean to withdraw collateral or not.
     *
     */
    function payOutstandingDebt(
        address _shortToken,
        address _paymentToken,
        uint256 _paymentAmount,
        bool _withdrawCollateral
    )
        public
        userOnly
        returns (bool)
    {
        require(userPositions[_shortToken].backingBaseAmount == 0, "Position is still open.");
        require(_paymentToken == _shortToken || _paymentToken == baseToken, "Pay with short or base token.");

        // Repay debt
        if (_paymentToken == _shortToken) {
            SafeTransferLib.safeTransferFrom(ERC20(_shortToken), msg.sender, address(this), _paymentAmount);
            repayAsset(_shortToken, _paymentAmount);
        } else {
            SafeTransferLib.safeTransferFrom(ERC20(baseToken), msg.sender, address(this), _paymentAmount);

            // Swap to short token
            (, uint256 amountOut) = swapExactInput(baseToken, _shortToken, _paymentAmount);

            repayAsset(_shortToken, amountOut);
        }

        // Optionally withdraw collateral
        if (_withdrawCollateral) {
            uint256 withdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);
            withdraw(withdrawalAmount);
        }

        // 3. Update accounting
        if (getOutstandingDebt(_shortToken) == 0) {
            userPositions[_shortToken].hasDebt = false;
        }

        return true;
    }

    /**
     * @dev  This function returns a list of user's positions and their associated accounting data.
     * @return aggregatedPositionData A list of user's positions and their associated accounting data.
     *
     */
    function getAccountingData() external view userOnly returns (PositionData[] memory) {
        address[] memory _openedShortPositions = openedShortPositions; // Optimizes gas
        PositionData[] memory aggregatedPositionData = new PositionData[](_openedShortPositions.length);
        for (uint256 i = 0; i < _openedShortPositions.length; i++) {
            PositionData storage position = userPositions[_openedShortPositions[i]];
            aggregatedPositionData[i] = position;
        }
        return aggregatedPositionData;
    }

    /**
     * @dev  This function allows a user to withdraw collateral on their Aave account, up to an
     * amount that does not raise their debt-to-collateral ratio above 70%.
     * @param _amount The amount of collateral (in Wei) the user wants to withdraw.
     *
     */
    function withdrawCollateral(uint256 _amount) public userOnly {
        uint256 maxWithdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);

        require(_amount <= maxWithdrawalAmount, "Exceeds max withdrawal amount.");

        withdraw(_amount);
    }
}
