// contracts/ShaaveChild.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// Local Imports
import "./libraries/logic/ShaaveUtilities.sol";

// External Package Imports
import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/access/Ownable.sol";
import "@openzeppelin-contracts/security/ReentrancyGuard.sol";
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

/// @title shAave child contract, owned by the ShaaveParent
contract ShaaveChild is Ownable, ReentrancyGuard {

    // -- ShaaveChild Variables --
    struct PositionData {
        // -- Arrays related to adding to a position --
        uint[] shortTokenAmountsSwapped;
        uint[] baseAmountsReceived;
        uint[] collateralAmounts;
        // -- Arrays related to reducing a position --
        uint[] baseAmountsSwapped;
        uint[] shortTokenAmountsReceived;
        // -- Miscellaneous -- 
        uint backingBaseAmount;
    }

    address private immutable user;
    mapping(address => PositionData) public userPositions;
    mapping(address => address) private userContracts;
    address[] private childContracts;
    address[] private openShortPositions;    //TODO: Add and remove from this

    // -- Aave Variables --
    address public baseTokenAddress = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;    // Goerli Aave USDC
    address public aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;           // Goerli Aave Pool Address
    address public aaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;         // Goerli Aave Oracle Address

    // -- Uniswap Variables --
    uint24 constant poolFee = 3000;
    ISwapRouter public immutable swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;  // Goerli

    // Events
    event BorrowSuccess(address borrowTokenAddress, uint amount);
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);
    event PositionAddedSuccess(address user, address shortTokenAddress, uint amount);
    event ErrorString(string errorMessage, string executionInsight);
    event LowLevelError(bytes errorData, string executionInsight);

    constructor(address _user) {
        user = _user;
    }

    /** 
    * @dev This function is used to short an asset; it's exclusively called by ShaavePerent.addShortPosition().
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _collateralTokenAmount The amount of collateral that will be used for adding to a short position.
    * @notice currentAssetPrice is the current price of the short token, in terms of the collateral token.
    * @notice borrowAmount is the amount of the short token that will be borrowed from Aave.
    **/
    function short(
        address _shortTokenAddress,
        uint _collateralTokenAmount,
        address _userAddress
    ) public onlyOwner returns (bool) {

        // 1. Calculate the amount that can be borrowed
        uint priceOfShortTokenInBase = ShaaveUtilities.getAssetPriceInBase(baseTokenAddress, _shortTokenAddress);
        uint loanToValueRatio = 70;
        uint borrowAmount = (((_collateralTokenAmount * loanToValueRatio) / 100) / priceOfShortTokenInBase) * 1e18;

        // 2. Since parent supplied collateral on this contract's behalf, borrow asset
        IPool(aavePoolAddress).borrow(_shortTokenAddress, borrowAmount, 2, 0, address(this));
        emit BorrowSuccess(_userAddress, _shortTokenAddress, _shortTokenAmount);

        // 3. Swap borrowed asset for collateral token
        (uint amountIn, uint amountOut) = swapExactInput(swapRouter, _shortTokenAddress, baseTokenAddress, borrowAmount, poolFee);
        emit PositionAddedSuccess(_userAddress, _shortTokenAddress, _shortTokenAmount);

        // 4. Update user's accounting
        // Check if this contract has any debt tokens... If not, add it to array. 
        userPositions[_shortTokenAddress].shortTokenAmountsSwapped.push(amountIn);
        userPositions[_shortTokenAddress].baseAmountsReceived.push(amountOut);
        userPositions[_shortTokenAddress].collateralAmounts.push(_collateralTokenAmount);
        userPositions[_shortTokenAddress].backingBaseAmount += amountOut;
    }


    /** 
    * @dev This function is used to reduce a short position.
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _percentageReduction The percentage reduction of the user's short position; 100% constitutes closing out the position
    * @notice shortTokenReductionAmount The amount of short token that the position is being reduced by.
    * @notice totalShortTokenDebt The total amount that this contract owes Aave (principle + interest).
    **/
    function reducePosition(
        address _shortTokenAddress,
        uint _percentageReduction,
        bool _withdrawCollateral
    ) public returns (bool) {

        require(msg.sender == user, "Unauthorized.");
        require(_percentageReduction <= 100, "Percentage cannot exceed 100.");

        // 1. Fetch debtToken address
        address variableDebtTokenAddress = IPool(aavePoolAddress).getReserveData(_shortTokenAddress)[10];

        // 2. Fetch msg.sender's debtToken balance. This value represents what the user owes (principle + interest)
        uint totalShortTokenDebt = IERC20(variableDebtTokenAddress).balanceOf(address(this));

        // 3. Calculate the amount of short tokens the short position will be reduced by
        uint shortTokenReductionAmount = (totalShortTokenDebt * _percentageReduction) / 100;

        // 4. Obtain child contract's total base token balance; it will be used during the swap process
        uint positionbackingBaseAmount = userPositions[_shortTokenAddress].backingBaseAmount;

        // 5. Swap short tokens for base tokens
        (uint amountIn, uint amountOut) = swapToShortToken(_shortTokenAddress, baseTokenAddress, shortTokenReductionAmount, positionbackingBaseAmount);

        // 6. Update child contract's accounting
        // If it has no debtTokens, remove from open positions array.
        userPositions[_shortTokenAddress].baseAmountsSwapped.push(amountIn);
        userPositions[_shortTokenAddress].shortTokenAmountsReceived.push(amountOut);
        userPositions[_shortTokenAddress].backingBaseAmount -= amountIn;

        // 7. Repay Aave loan with the amount of short token received from Uniswap
        IPool(aavePoolAddress).repay(_shortTokenAddress, amountOut, 2, address(this));

        // 8. If the trade was profitable, repay user a percentage of profits
        uint gains = calculatePositionGains(_shortTokenAddress, variableDebtTokenAddress, _percentageReduction);

        // 9. Withdraw correct percentage of collateral, and return to user
        if (_withdrawCollateral) {
            uint withdrawalAmount = calculateCollateralWithdrawAmount(shortTokenReductionAmount);

            if (withdrawalAmount > 0) {
                IPool(aavePoolAddress).withdraw(baseTokenAddress, withdrawalAmount, user);
            }
        }
        
        // 10. Pay out gains to the user
        if (gains > 0) {
            userPositions[_shortTokenAddress].backingBaseAmount -= gains;
            user.transfer(gains);
        }
    }

    /** 
    * @dev This function is used to calculate a trade's gains.
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _variableDebtTokenAddress The address of Aave's variable debt token contract, for the given short token.
    * @param _percentageReduction The percentage reduction of the user's short position; 100% constitutes closing out the position.
    * @return gains The gains the trade at hand yielded; this value will be paid out to the user.
    * @notice debtValueBase This total debt's value in the base asset (collateral asset), for a specific asset.
    * @notice positionbackingBaseAmount The amount of base (collateral) asset this contract has allocated for a specific asset short position.
    **/
    function calculatePositionGains(
        address _shortTokenAddress,
        address _variableDebtTokenAddress,
        uint _percentageReduction
    ) private returns (uint gains) {

        uint priceOfShortTokenInBase = ShaaveUtilities.getAssetPriceInBase(baseTokenAddress, _shortTokenAddress);
        uint totalShortTokenDebt = IERC20(_variableDebtTokenAddress).balanceOf(address(this));
        uint debtValueBase = priceOfShortTokenInBase * totalShortTokenDebt;
        uint positionbackingBaseAmount = userPositions[_shortTokenAddress].backingBaseAmount;

        if (positionbackingBaseAmount > debtValueBase) {
            gains = (_percentageReduction * (positionbackingBaseAmount - debtValueBase)) / 100;
        } else {
            gains = 0;
        }
    }


    /** 
    * @dev This function is used to calculate the amount of collateral that can be withdrawn at any given sell event.
    *      It's structured to always withdraw the maximum amount of collateral, such that the ratio of total debt to 
    *      total collateral remains below 70%.
    * @return withdrawalAmount The gains the trade at hand yielded; this value will be paid out to the user.
    * @notice totalDebtBase is the value of debt, in the base (collateral) token across all borrowed assets.
    **/
    function calculateCollateralWithdrawAmount() private returns (uint withdrawalAmount) {
        
        (uint totalCollateralBase, uint totalDebtBase, , , , ) = IPool(aavePoolAddress).getUserAccountData(user);

        int maxWithdrawal = totalCollateralBase - (totalDebtBase / 0.70);  //FIXME: may need to scale here

        if (maxWithdrawal > 0) {
            withdrawalAmount = maxWithdrawal;
        } else {
            withdrawalAmount = 0;
        }
    }

    /** 
    * @param _shortTokenAddress The address of the token that this function is attempting to obtain from Uniswap.
    * @param _shortTokenReductionAmount The amount of the token, in WEI, that this function is attempting to obtain from Uniswap.
    * @return amountIn the amountIn to supply to uniswap when swapping to short tokens.
    **/
    function getAmountIn(uint _shortTokenReductionAmount, address _shortTokenAddress, uint _positionbackingBaseAmount) private returns (uint amountIn) {
        
        uint priceOfShortTokenInBase = ShaaveUtilities.getAssetPriceInBase(baseTokenAddress, _shortTokenAddress);

        uint shortTokenReductionAmountBase = priceOfShortTokenInBase * _shortTokenReductionAmount;

        if (shortTokenReductionAmountBase <= _positionbackingBaseAmount) {
            amountIn = shortTokenReductionAmountBase * 1e18;
        } else {
            amountIn = _positionbackingBaseAmount;
        }
    }

    /** 
    * @param _tokenInAddress The address of the token that this function is attempting to give to Uniswap
    * @param _tokenOutAddress The address of the token that this function is attempting to obtain from Uniswap
    * @param _tokenInAmount The amount of the token, in WEI, that this function is attempting to give to Uniswap
    * @return amountIn The amount of tokens supplied to Uniswap for a desired token output amount
    * @return amountOut The amount of tokens received from Uniswap
    **/
    function swapExactInput(
        address _tokenInAddress,
        address _tokenOutAddress,
        uint _tokenInAmount
    ) private returns (uint amountIn, uint amountOut) {

        TransferHelper.safeApprove(_tokenInAddress, address(swapRouter), _tokenInAmount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenInAddress,
                tokenOut: _tokenOutAddress,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _tokenInAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        (amountIn, amountOut) = (_tokenInAmount, swapRouter.exactInputSingle(params));
    }

    /** 
    * @param _tokenOutAddress The address of the token that this function is attempting to obtain from Uniswap
    * @param _tokenOutAmount The amount of the token, in WEI, that this function is attempting to obtain from Uniswap
    * @param _tokenInAddress The address of the token that this function is attempting to spend for output tokens.
    * @param _amountInMaximum The maximum amount of input tokens this contract is willing to spend for output tokens.
    * @return amount The amount returned from Uniswap (this can be an amountIn or amountOut, denoted by amountType)
    * @return amountType The type of amount (0 = amountIn, 1 = amountOut) 
    **/
    function swapToShortToken(
        address _tokenOutAddress,
        address _tokenInAddress,
        uint _tokenOutAmount,
        uint _amountInMaximum
    ) private returns (uint amountIn, uint amountOut) {
        
        TransferHelper.safeApprove(_tokenInAddress, address(swapRouter), _amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: _tokenInAddress,
                tokenOut: _tokenOutAddress,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: _tokenOutAmount,
                amountInMaximum: _amountInMaximum,
                sqrtPriceLimitX96: 0
            });
        
        try swapRouter.exactOutputSingle(params) returns (uint returnedAmountIn) {

            emit SwapSuccess(msg.sender, _tokenInAddress, returnedAmountIn, _tokenOutAddress, _tokenOutAmount);
            (amountIn, amountOut) = (returnedAmountIn, _tokenOutAmount);

        } catch Error(string memory reason) {

            amountIn = getAmountIn(_tokenOutAmount, _tokenOutAddress, _amountInMaximum);
            emit ErrorString(reason, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() now.");
            (amountIn, amountOut) = swapExactInput(_tokenInAddress, _tokenOutAddress, amountIn);

        } catch (bytes memory reason) {

            amountIn = getAmountIn(_tokenOutAmount, _tokenOutAddress, _amountInMaximum);
            emit LowLevelError(reason, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() now.");
            (amountIn, amountOut) = swapExactInput(_tokenInAddress, _tokenOutAddress, amountIn);

        }
    }


    /** 
    * @dev  This function repays all child's outstanding (per asset) debt, in the case where all base token has been used already.
    * @param _shortTokenAddress The address of the token the user has shorted.
    * @param _paymentToken The address of the token used to repay outstanding debt (either base token or short token).
    **/
    function repayOutstandingDebt(address _shortTokenAddress, address _paymentToken, uint _paymentAmount, bool _withdrawCollateral) public adminOnly returns (bool) {
        require(userPositions[_shortTokenAddress].backingBaseAmount == 0, "Position is still open. Use reducePosition() first. If any debt remains after, then use repayOutstandingDebt()");
        require(_paymentToken == _shortTokenAddress || _paymentToken == baseTokenAddress, "Payment must be in the form of either the short token or the collateral token.");

        if (_paymentToken == _shortTokenAddress) {
            // 1. Transfer short tokens to this contract, so it can repay the Aave loan.
            IERC20(_shortTokenAddress).transferFrom(msg.sender, address(this), _paymentAmount);

            // 2. Repay Aave loan with the amount of short token supplied by the user.
            IPool(aavePoolAddress).repay(_shortTokenAddress, _paymentAmount, 2, address(this));

        } else {
            // 1. Transfer base tokens to this contract, so it can swap them for short tokens.
            IERC20(baseTokenAddress).transferFrom(msg.sender, address(this), _paymentAmount);

            // 2. Swap base tokens for short tokens, that will be used to repay the Aave loan.
            (amountIn, amountOut) = swapExactInput(baseTokenAddress, _shortTokenAddress, _paymentAmount);

            // 3. Repay Aave loan with the amount of short tokens received from Uniswap.
            IPool(aavePoolAddress).repay(_shortTokenAddress, amountOut, 2, address(this));
        }

        if (_withdrawCollateral) {
            uint withdrawalAmount = calculateCollateralWithdrawAmount(shortTokenReductionAmount);
            IPool(aavePoolAddress).withdraw(baseTokenAddress, withdrawalAmount, user);
        }
    }



    function getAccountingData() public returns (uint[][] accountingData) {}
    

}