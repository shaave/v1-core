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
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
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
        // -- Miscellaneous -- 
        uint backingBaseAmount;
        address shortTokenAddress;
        bool hasDebt;
    }

    address private immutable user;
    mapping(address => PositionData) public userPositions;
    mapping(address => address) private userContracts;
    address[] private childContracts;
    address[] private openShortPositions;

    // -- Aave Variables --
    address public baseTokenAddress = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;    // Goerli Aave USDC
    address public aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;           // Goerli Aave Pool Address
    address public aaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;         // Goerli Aave Oracle Address

    // -- Uniswap Variables --
    uint24 constant poolFee = 3000;
    ISwapRouter public immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);  // Goerli

    // Events
    event BorrowSuccess(address user, address borrowTokenAddress, uint amount);
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
    * @param _collateralTokenAmount The amount of collateral (in WEI) that will be used for adding to a short position.
    * @notice currentAssetPrice is the current price of the short token, in terms of the collateral token.
    * @notice borrowAmount is the amount of the short token that will be borrowed from Aave.
    **/
    function short(
        address _shortTokenAddress,
        uint _collateralTokenAmount,
        address _userAddress
    ) public onlyOwner returns (bool) {

        // 1. Calculate the amount that can be borrowed
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(baseTokenAddress);     // Wei
        uint loanToValueRatio = 70;
        uint borrowAmount = ((_collateralTokenAmount * loanToValueRatio).dividedBy(100, 0)).dividedBy(priceOfShortTokenInBase, 18);    // Wei

        // 2. Since parent supplied collateral on this contract's behalf, borrow asset
        IPool(aavePoolAddress).borrow(_shortTokenAddress, borrowAmount, 2, 0, address(this));
        emit BorrowSuccess(_userAddress, _shortTokenAddress, borrowAmount);

        // 3. Swap borrowed asset for collateral token
        (uint amountIn, uint amountOut) = swapExactInput(_shortTokenAddress, baseTokenAddress, borrowAmount);
        emit PositionAddedSuccess(_userAddress, _shortTokenAddress, borrowAmount);

        // 4. Update user's accounting
        if (userPositions[_shortTokenAddress].shortTokenAddress == address(0)) {
            userPositions[_shortTokenAddress].shortTokenAddress = _shortTokenAddress;
        }

        if (!userPositions[_shortTokenAddress].hasDebt) {
            userPositions[_shortTokenAddress].hasDebt = true;
        }

        if (!openShortPositions.includes(_shortTokenAddress)) {
            openShortPositions.push(_shortTokenAddress);
        }
            
        userPositions[_shortTokenAddress].shortTokenAmountsSwapped.push(amountIn);
        userPositions[_shortTokenAddress].baseAmountsReceived.push(amountOut);
        userPositions[_shortTokenAddress].collateralAmounts.push(_collateralTokenAmount);
        userPositions[_shortTokenAddress].backingBaseAmount += amountOut;
    }


    /** 
    * @dev This function is used to reduce a short position.
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _percentageReduction The percentage reduction of the user's short position; 100% constitutes closing out the position
    * @param _withdrawCollateral A boolean to withdraw collateral or not.
    * @notice shortTokenReductionAmount The amount of short token that the position is being reduced by.
    * @notice totalShortTokenDebt The total amount that this contract owes Aave (principle + interest).
    **/
    function reducePosition(
        address _shortTokenAddress,
        uint _percentageReduction,
        bool _withdrawCollateral
    ) public adminOnly returns (bool) {

        require(_percentageReduction <= 100, "Percentage cannot exceed 100.");

        // 1. Fetch this contract's outstanding debt for the supplied short token.
        uint totalShortTokenDebt = getOutstandingDebt(_shortTokenAddress);

        // 2. Calculate the amount of short tokens the short position will be reduced by
        uint shortTokenReductionAmount = (totalShortTokenDebt * _percentageReduction).dividedBy(100, 0);    // Wei

        // 3. Obtain child contract's total base token balance; it will be used during the swap process
        uint backingBaseAmount = userPositions[_shortTokenAddress].backingBaseAmount;

        // 4. Swap short tokens for base tokens
        (uint amountIn, uint amountOut) = swapToShortToken(_shortTokenAddress, baseTokenAddress, shortTokenReductionAmount, backingBaseAmount);

        // 5. Repay Aave loan with the amount of short token received from Uniswap
        IPool(aavePoolAddress).repay(_shortTokenAddress, amountOut, 2, address(this));

        uint debtAfterRepay = getOutstandingDebt(_shortTokenAddress);

        // 6. Update child contract's accounting
        userPositions[_shortTokenAddress].baseAmountsSwapped.push(amountIn);
        userPositions[_shortTokenAddress].shortTokenAmountsReceived.push(amountOut);
        userPositions[_shortTokenAddress].backingBaseAmount -= amountIn;

        if (userPositions[_shortTokenAddress].backingBaseAmount == 0) {
            openShortPositions.removeAddress(_shortTokenAddress);
        }

        if (debtAfterRepay == 0) {
            userPositions[_shortTokenAddress].hasDebt = false;
        }
        
        // 7. If the trade was profitable, repay user a percentage of profits
        uint gains = ReturnCapital.calculatePositionGains(_shortTokenAddress, baseTokenAddress, _percentageReduction, userPositions[_shortTokenAddress].backingBaseAmount, debtAfterRepay);

        // 8. Withdraw correct percentage of collateral, and return to user
        if (_withdrawCollateral) {
            uint withdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(address(this));

            if (withdrawalAmount > 0) {
                IPool(aavePoolAddress).withdraw(baseTokenAddress, withdrawalAmount, user);
            }
        }
        
        // 9. Pay out gains to the user
        if (gains > 0) {
            IERC20(baseTokenAddress).transfer(msg.sender, gains.dividedBy(1e12, 0));
            userPositions[_shortTokenAddress].backingBaseAmount -= gains;
        }
    }

    /** 
    * @param _shortTokenAddress The address of the token that this function is attempting to obtain from Uniswap.
    * @param _shortTokenReductionAmount The amount of the token, in WEI, that this function is attempting to obtain from Uniswap.
    * @return amountIn the amountIn to supply to uniswap when swapping to short tokens.
    **/
    function getAmountIn(uint _shortTokenReductionAmount, address _shortTokenAddress, uint _backingBaseAmount) private returns (uint amountIn) {
        
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(baseTokenAddress);     // Wei

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
    * @param _paymentAmount The amount that's sent to repay the outstanding debt.
    * @param _withdrawCollateral A boolean to withdraw collateral or not.
    **/
    function repayOutstandingDebt(address _shortTokenAddress, address _paymentToken, uint _paymentAmount, bool _withdrawCollateral) public adminOnly returns (bool) {
        require(userPositions[_shortTokenAddress].backingBaseAmount == 0, "Position is still open. Use reducePosition() first. If any debt remains after, then use repayOutstandingDebt()");
        require(_paymentToken == _shortTokenAddress || _paymentToken == baseTokenAddress, "Payment must be in the form of either the short token or the collateral token.");
        
        // 1. Repay debt.
        if (_paymentToken == _shortTokenAddress) {
            // i. Transfer short tokens to this contract, so it can repay the Aave loan.
            IERC20(_shortTokenAddress).transferFrom(msg.sender, address(this), _paymentAmount);

            // ii. Repay Aave loan with the amount of short token supplied by the user.
            IPool(aavePoolAddress).repay(_shortTokenAddress, _paymentAmount, 2, address(this));

        } else {
            // i. Transfer base tokens to this contract, so it can swap them for short tokens.
            IERC20(baseTokenAddress).transferFrom(msg.sender, address(this), _paymentAmount);

            // ii. Swap base tokens for short tokens, that will be used to repay the Aave loan.
            (uint amountIn, uint amountOut) = swapExactInput(baseTokenAddress, _shortTokenAddress, _paymentAmount);

            // iii. Repay Aave loan with the amount of short tokens received from Uniswap.
            IPool(aavePoolAddress).repay(_shortTokenAddress, amountOut, 2, address(this));
        }

        // 2. Optionally withdraw collateral.
        if (_withdrawCollateral) {
            uint withdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(address(this));
            IPool(aavePoolAddress).withdraw(baseTokenAddress, withdrawalAmount, user);
        }

        // 3. Update accounting
        if (getOutstandingDebt(_shortTokenAddress) == 0) {
            userPositions[_shortTokenAddress].hasDebt = false;
        }
    }

    /** 
    * @dev  This function (for internal and external use) returns the this contract's total debt for a given short token.
    * @param _shortTokenAddress The address of the token the user has shorted.
    * @return outStandingDebt This contract's total debt for a given short token.
    **/
    function getOutstandingDebt(address _shortTokenAddress) public view adminOnly returns (uint outstandingDebt) {
        address variableDebtTokenAddress = IPool(aavePoolAddress).getReserveData(_shortTokenAddress).variableDebtTokenAddress;
        outstandingDebt = IERC20(variableDebtTokenAddress).balanceOf(address(this));
    }

    function getOutstandingDebtBase(address _shortTokenAddress) public view adminOnly returns (uint outstandingDebtBase) {
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(baseTokenAddress);     // Wei
        uint totalShortTokenDebt = getOutstandingDebt(_shortTokenAddress);
        // TODO: finish writting this
    }


    /** 
    * @dev  This function returns a list of user's positions and their associated accounting data.
    * @return aggregatedPositionData A list of user's positions and their associated accounting data.
    **/
    function getAccountingData() external view adminOnly returns (PositionData[] memory) {

        PositionData[] memory aggregatedPositionData = new PositionData[](openShortPositions.length);
        for (uint i = 0; i < openShortPositions.length; i++) {
                PositionData storage position = userPositions[openShortPositions[i]];
                aggregatedPositionData[i] = position;
        }
        return aggregatedPositionData;
    }

    modifier adminOnly() {
        require(msg.sender == user, "Unauthorized.");
        _;
    }

}