// contracts/ShaaveChild.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// Local Imports
import "./libraries/ShaavePricing.sol";
import "./libraries/ReturnCapital.sol";
import "./libraries/AddressArray.sol";

// External Package Imports
import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

/// @title shAave child contract, owned by the ShaaveParent
contract ShaaveChild is Ownable {
    using AddressArray for address[];
    using ShaavePricing for address;
    using Math for uint;


    // -- ShaaveChild Variables --
    struct PositionData {
        // -- Arrays related to adding to a position --
        uint[] shortTokenAmountsSwapped;
        uint[] baseAmountsReceived;
        uint[] collateralAmounts;
        // -- Arrays related to reducing a position --
        uint[] baseAmountsSwapped;
        uint[] shortTokenAmountsReceived;
        // -- Orientational --
        address shortTokenAddress;
        address baseTokenAddress;
        // -- Miscellaneous -- 
        uint backingBaseAmount;
    }

    address private immutable user;
    mapping(address => mapping(address => PositionData)) public userPositions;
    mapping(address => address) private userContracts;
    address[] private openShortPositions;
    address[] private baseTokens;

    // -- Aave Variables --
    address public aavePoolAddress;
    address public aaveOracleAddress;

    // -- Uniswap Variables --
    uint24 public immutable poolFee;
    ISwapRouter public immutable swapRouter;  

    // Events
    event BorrowSuccess(address user, address borrowTokenAddress, uint amount);
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);
    event PositionAddedSuccess(address user, address shortTokenAddress, uint amount);
    event ErrorString(string errorMessage, string executionInsight);
    event LowLevelError(bytes errorData, string executionInsight);

    constructor(address _user, address _aavePoolAddress, address _aaveOracleAddress) {
        user = _user;
        aavePoolAddress = _aavePoolAddress;
        aaveOracleAddress = _aaveOracleAddress;
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Goerli
        poolFee = 3000;
    }

    /** 
    * @dev This function is used to short an asset; it's exclusively called by ShaavePerent.addShortPosition().
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _baseTokenAddress The address of the token that's used for collateral.
    * @param _baseTokenAmount The amount of collateral (in WEI) that will be used for adding to a short position.
    * @param _baseLoanToValueRatio The Shaave-imposed loan to value ratio (LTV) for the supplied collateral token, _baseTokenAddress.
    * @param _userAddress The address of the end user.
    * @notice borrowAmount is the amount of the short token that will be borrowed from Aave.
    **/
    function short(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _baseTokenAmount,
        uint _baseLoanToValueRatio,
        address _userAddress
    ) public onlyOwner returns (bool) {
        // 1. Calculate the amount that can be borrowed
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(_baseTokenAddress);     // Wei
        uint borrowAmount = ((_baseTokenAmount * _baseLoanToValueRatio).dividedBy(100, 0)).dividedBy(priceOfShortTokenInBase, 18);    // Wei

        // 2. Since parent supplied collateral on this contract's behalf, borrow asset
        IPool(aavePoolAddress).borrow(_shortTokenAddress, borrowAmount, 2, 0, address(this));
        emit BorrowSuccess(_userAddress, _shortTokenAddress, borrowAmount);

        // 3. Swap borrowed asset for collateral token
        (uint amountIn, uint amountOut) = swapExactInput(_shortTokenAddress, _baseTokenAddress, borrowAmount);
        emit PositionAddedSuccess(_userAddress, _shortTokenAddress, borrowAmount);

        // 4. Update user's accounting
        if (userPositions[_shortTokenAddress][_baseTokenAddress].shortTokenAddress == address(0)) {
            userPositions[_shortTokenAddress][_baseTokenAddress].shortTokenAddress = _shortTokenAddress;
        }

        if (!openShortPositions.includes(_shortTokenAddress)) {
            openShortPositions.push(_shortTokenAddress);
        }

        if (!baseTokens.includes(_baseTokenAddress)) {
            baseTokens.push(_baseTokenAddress);
        }
            
        userPositions[_shortTokenAddress][_baseTokenAddress].shortTokenAmountsSwapped.push(amountIn);
        userPositions[_shortTokenAddress][_baseTokenAddress].baseAmountsReceived.push(amountOut);
        userPositions[_shortTokenAddress][_baseTokenAddress].collateralAmounts.push(_baseTokenAmount);
        userPositions[_shortTokenAddress][_baseTokenAddress].backingBaseAmount += amountOut;

        return true;
    }


    /** 
    * @dev This function is used to reduce a short position.
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _baseTokenAddress The address of the token that's used for collateral.
    * @param _percentageReduction The percentage reduction of the user's short position; 100% constitutes closing out the position
    * @param _withdrawCollateral A boolean to withdraw collateral or not.
    * @notice shortTokenReductionAmount The amount of short token that the position is being reduced by.
    * @notice totalShortTokenDebt The total amount that this contract owes Aave (principle + interest).
    **/
    function reducePosition(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _percentageReduction,
        bool _withdrawCollateral
    ) public adminOnly returns (bool) {
        require(_percentageReduction <= 100, "Percentage cannot exceed 100.");

        // 1. Fetch this contract's outstanding debt for the supplied short token.
        uint totalShortTokenDebt = getOutstandingDebt(_shortTokenAddress);

        // 2. Calculate the amount of short tokens the short position will be reduced by
        uint shortTokenReductionAmount = (totalShortTokenDebt * _percentageReduction).dividedBy(100, 0);    // Wei

        // 3. Swap base tokens for short tokens
        uint backingBaseAmount = userPositions[_shortTokenAddress][_baseTokenAddress].backingBaseAmount;
        (uint amountIn, uint amountOut) = swapToShortToken(_shortTokenAddress, _baseTokenAddress, shortTokenReductionAmount, backingBaseAmount);

        // 4. Repay Aave loan with the amount of short token received from Uniswap
        IERC20(_shortTokenAddress).approve(aavePoolAddress, amountOut);
        IPool(aavePoolAddress).repay(_shortTokenAddress, amountOut, 2, address(this));
        
        // 5. Update child contract's accounting
        userPositions[_shortTokenAddress][_baseTokenAddress].baseAmountsSwapped.push(amountIn);
        userPositions[_shortTokenAddress][_baseTokenAddress].shortTokenAmountsReceived.push(amountOut);
        userPositions[_shortTokenAddress][_baseTokenAddress].backingBaseAmount -= amountIn;

        bool positionIsOpen = false;
        for (uint i = 0; i < baseTokens.length; i++) {
            if (userPositions[_shortTokenAddress][baseTokens[i]].backingBaseAmount != 0) {
                positionIsOpen = true;
                break;
            }
        }
        if (!positionIsOpen) {
            openShortPositions.removeAddress(_shortTokenAddress);
        }
        
        // 7. Withdraw correct percentage of collateral, and return to user
        if (_withdrawCollateral) {
            uint withdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(address(this));

            if (withdrawalAmount > 0) {
                IPool(aavePoolAddress).withdraw(_baseTokenAddress, withdrawalAmount, user);
            }
        }
        
        // 8. Pay out gains to the user
        uint debtAfterRepay = getOutstandingDebt(_shortTokenAddress);
        uint gains = ReturnCapital.calculatePositionGains(_shortTokenAddress, _baseTokenAddress, _percentageReduction, backingBaseAmount, debtAfterRepay);

        if (gains > 0) {
            IERC20(_baseTokenAddress).transfer(msg.sender, gains.dividedBy(1e12, 0));
            userPositions[_shortTokenAddress][_baseTokenAddress].backingBaseAmount -= gains;
        }
        
        return true;
    }

    /** 
    * @param _shortTokenAddress The address of the token that this function is attempting to obtain from Uniswap.
    * @param _baseTokenAddress The address of the base token.
    * @param _shortTokenReductionAmount The amount of the token, in WEI, that this function is attempting to obtain from Uniswap.
    * @return amountIn the amountIn to supply to uniswap when swapping to short tokens.
    **/
    function getAmountIn(uint _shortTokenReductionAmount, address _baseTokenAddress, address _shortTokenAddress, uint _backingBaseAmount) private view returns (uint amountIn) {
        
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(_baseTokenAddress);     // Wei

        uint shortTokenReductionAmountBase = (priceOfShortTokenInBase * _shortTokenReductionAmount).dividedBy(1e18, 0);    // Wei

        if (shortTokenReductionAmountBase <= _backingBaseAmount) {
            amountIn = shortTokenReductionAmountBase * 1e18;
        } else {
            amountIn = _backingBaseAmount;
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
    * @return amountIn The amount of tokens supplied to Uniswap for a desired token output amount
    * @return amountOut The amount of tokens received from Uniswap
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

        } catch Error(string memory message) {
            
            emit ErrorString(message, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() instead.");
            amountIn = getAmountIn(_tokenOutAmount, _tokenInAddress, _tokenOutAddress, _amountInMaximum);
            (amountIn, amountOut) = swapExactInput(_tokenInAddress, _tokenOutAddress, amountIn);

        } catch (bytes memory data) {
            emit LowLevelError(data, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() instead.");
            amountIn = getAmountIn(_tokenOutAmount, _tokenInAddress, _tokenOutAddress, _amountInMaximum);
            (amountIn, amountOut) = swapExactInput(_tokenInAddress, _tokenOutAddress, amountIn);
        
        }
    }


    /** 
    * @dev  This function repays all child's outstanding (per asset) debt, in the case where all base token has been used already.
    * @param _shortTokenAddress The address of the token the user has shorted.
    * @param _baseTokenAddress The address of the base token.
    * @param _paymentToken The address of the token used to repay outstanding debt (either base token or short token).
    * @param _paymentAmount The amount that's sent to repay the outstanding debt.
    * @param _withdrawCollateral A boolean to withdraw collateral or not.
    **/
    function payOutstandingDebt(address _shortTokenAddress, address _baseTokenAddress, address _paymentToken, uint _paymentAmount, bool _withdrawCollateral) public adminOnly returns (bool) {
        require(userPositions[_shortTokenAddress][_baseTokenAddress].backingBaseAmount == 0, "Position is still open.");
        
        // 1. Repay debt.
        if (_paymentToken == _shortTokenAddress) {
            // i. Transfer short tokens to this contract, so it can repay the Aave loan.
            IERC20(_shortTokenAddress).transferFrom(msg.sender, address(this), _paymentAmount);

            // ii. Repay Aave loan with the amount of short token supplied by the user.
            IERC20(_shortTokenAddress).approve(aavePoolAddress, _paymentAmount);
            IPool(aavePoolAddress).repay(_shortTokenAddress, _paymentAmount, 2, address(this));

        } else {
            // i. Transfer base tokens to this contract, so it can swap them for short tokens.
            IERC20(_baseTokenAddress).transferFrom(msg.sender, address(this), _paymentAmount);

            // ii. Swap base tokens for short tokens, that will be used to repay the Aave loan.
            ( , uint amountOut) = swapExactInput(_baseTokenAddress, _shortTokenAddress, _paymentAmount);


            // iii. Repay Aave loan with the amount of short tokens received from Uniswap.
            IERC20(_shortTokenAddress).approve(aavePoolAddress, amountOut);
            IPool(aavePoolAddress).repay(_shortTokenAddress, amountOut, 2, address(this));
        }

        // 2. Optionally withdraw collateral.
        if (_withdrawCollateral) {
            uint withdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(address(this));
            IPool(aavePoolAddress).withdraw(_baseTokenAddress, withdrawalAmount, user);
        }
        return true;
    }

    /** 
    * @dev  This function (for internal and external use) returns the this contract's total debt for a given short token.
    * @param _shortTokenAddress The address of the token the user has shorted.
    * @return outstandingDebt This contract's total debt for a given short token.
    **/
    function getOutstandingDebt(address _shortTokenAddress) public view adminOnly returns (uint outstandingDebt) {
        address variableDebtTokenAddress = IPool(aavePoolAddress).getReserveData(_shortTokenAddress).variableDebtTokenAddress;
        outstandingDebt = IERC20(variableDebtTokenAddress).balanceOf(address(this));
    }


    /** 
    * @dev  This function returns the this contract's total debt, in terms of the base token (in Wei), for a given short token.
    * @param _shortTokenAddress The address of the token the user has shorted.
    * @param _baseTokenAddress The address of the base token.
    * @return outstandingDebtBase This contract's total debt, in terms the base token (in Wei), for a given short token.
    **/
    function getOutstandingDebtBase(address _shortTokenAddress, address _baseTokenAddress) public view adminOnly returns (uint outstandingDebtBase) {
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(_baseTokenAddress);               // Wei
        uint totalShortTokenDebt = getOutstandingDebt(_shortTokenAddress);                          // Wei
        outstandingDebtBase = (priceOfShortTokenInBase * totalShortTokenDebt).dividedBy(1e18, 0);   // Wei
    }


    /** 
    * @dev  This function returns a list of user's positions and their associated accounting data.
    * @return aggregatedPositionData A list of user's positions and their associated accounting data.
    **/
    function getAccountingData() external view adminOnly returns (PositionData[] memory) {
        uint appendIndex = 0;
        address[] memory _openShortPositions = openShortPositions;
        address[] memory _baseTokens = baseTokens;
        PositionData[] memory aggregatedPositionData = new PositionData[](_openShortPositions.length * _baseTokens.length);
        for (uint i = 0; i < _openShortPositions.length; i++) {
                for (uint j = 0; j < _baseTokens.length; j++) {
                    if (userPositions[_openShortPositions[i]][_baseTokens[j]].baseTokenAddress != address(0)) {
                        PositionData storage position = userPositions[_openShortPositions[i]][_baseTokens[j]];
                        aggregatedPositionData[appendIndex] = position;
                        appendIndex++;
                    }
                }
        }
        return aggregatedPositionData;
    }


    /** 
    * @dev  This function returns a list of data related to the Aave account that this contract has.
    **/
    function getAaveAccountData() public view adminOnly returns (uint totalCollateralBase, uint totalDebtBase, uint availableBorrowBase, uint currentLiquidationThreshold, uint ltv, uint healthFactor, uint maxWithdrawalAmount) {
        maxWithdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(address(this));
        (totalCollateralBase, totalDebtBase, availableBorrowBase, currentLiquidationThreshold, ltv, healthFactor) = IPool(aavePoolAddress).getUserAccountData(address(this));   // Must multiply by 1e10 to get Wei
    }

    /** 
    * @dev  This function allows a user to withdraw collateral on their Aave account, up to an
            amount that does not raise their debt-to-collateral ratio above 70%.
    * @param _withdrawAmount The amount of collateral (in Wei) the user wants to withdraw.
    * @param _baseTokenAddress The address of the base token, which is the collateral token.
    **/
    function withdrawCollateral(uint _withdrawAmount, address _baseTokenAddress) public adminOnly {
        uint maxWithdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(address(this));
        require(_withdrawAmount <= maxWithdrawalAmount, "Exceeds max withdraw amount.");

        IPool(aavePoolAddress).withdraw(_baseTokenAddress, _withdrawAmount, user);
    }

    modifier adminOnly() {
        require(msg.sender == user, "Unauthorized.");
        _;
    }

}