// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// Local Imports
import "./libraries/ShaavePricing.sol";
import "./libraries/ReturnCapital.sol";
import "./libraries/AddressArray.sol";
import "../interfaces/IwERC20.sol";

// External Package Imports
import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";


import "forge-std/console.sol";

/// @title shAave child contract, owned by the Parent
contract Child is Ownable {
    using AddressArray for address[];
    using ShaavePricing for address;
    using Math for uint;

    // -- Child Variables --
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

    
    mapping(address => address) private userContracts;
    address[] private childContracts;
    address[] private openedShortPositions;
    mapping(address => PositionData) public userPositions;

    // -- Constructor Variables --
    uint public immutable shaaveLTV;
    uint public immutable baseTokenConversion;  // To Wei
    address public immutable baseToken;
    address private immutable user;
    
    // -- Aave Constants --
    address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public constant AAVE_ORACLE = 0xb023e699F5a33916Ea823A16485e259257cA8Bd1; 

    // -- Uniswap Constants --
    address public constant UNISWAP_SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24 public constant POOL_FEE = 3000;
    ISwapRouter public constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);  

    // Events
    event BorrowSuccess(address user, address borrowTokenAddress, uint amount);
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);
    event PositionAddedSuccess(address user, address shortTokenAddress, uint amount);
    event ErrorString(string errorMessage, string executionInsight);
    event LowLevelError(bytes errorData, string executionInsight);

    constructor(address _user, address _baseToken, uint _baseTokenDecimals, uint _shaaveLTV) {
        user = _user;
        baseToken = _baseToken;
        baseTokenConversion = 10 ** (18 - _baseTokenDecimals);
        shaaveLTV = _shaaveLTV;
    }

    
    /** 
    * @dev This function is used to short an asset; it's exclusively called by ShaavePerent.addShortPosition().
    * @param _shortToken The address of the short token the user wants to reduce his or her position in.
    * @param _baseTokenAmount The amount of collateral (in WEI) that will be used for adding to a short position.
    * @notice currentAssetPrice is the current price of the short token, in terms of the collateral token.
    * @notice borrowAmount is the amount of the short token that will be borrowed from Aave.
    **/
    function short(
        address _shortToken,
        uint _baseTokenAmount,
        address _userAddress
    ) public onlyOwner returns (bool) {
        
        // 1. Calculate the amount that can be borrowed
        uint shortTokenConversion = (10 ** (18 - IwERC20(_shortToken).decimals()));
        uint priceOfShortTokenInBase = _shortToken.pricedIn(baseToken);     // Wei
        uint borrowAmount = ((_baseTokenAmount * baseTokenConversion * shaaveLTV) / 100).dividedBy(priceOfShortTokenInBase, 18) / shortTokenConversion;

        // 2. Since parent supplied collateral on this contract's behalf, borrow asset
        IPool(AAVE_POOL).borrow(_shortToken, borrowAmount, 2, 0, address(this));
        emit BorrowSuccess(_userAddress, _shortToken, borrowAmount);

        // 3. Swap borrowed asset for collateral token
        (uint amountIn, uint amountOut) = swapExactInput(_shortToken, baseToken, borrowAmount);
        emit PositionAddedSuccess(_userAddress, _shortToken, borrowAmount);


        // 4. Update user's accounting
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
    **/
    function reducePosition(
        address _shortToken,
        uint _percentageReduction,
        bool _withdrawCollateral
    ) public userOnly returns (bool) {
        require(_percentageReduction > 0 && _percentageReduction <= 100, "Invalid percentage.");

        // 1. Calculate the amount of short tokens the short position will be reduced by
        uint positionReduction = (getOutstandingDebt(_shortToken) * _percentageReduction) / 100;   // Uints: short token decimals

        // 2. Swap short tokens for base tokens
        (uint amountIn, uint amountOut) = swapToShortToken(_shortToken, baseToken, positionReduction, userPositions[_shortToken].backingBaseAmount);

        // 3. Repay Aave loan with the amount of short token received from Uniswap
        IERC20(_shortToken).approve(AAVE_POOL, amountOut);
        IPool(AAVE_POOL).repay(_shortToken, amountOut, 2, address(this));

        /// @dev shortTokenConversion = (10 ** (18 - IwERC20(_shortToken).decimals()))
        uint debtAfterRepay = getOutstandingDebt(_shortToken) * (10 ** (18 - IwERC20(_shortToken).decimals()));      // Wei, as that's what getPositionGains wants


        // 4. Withdraw correct percentage of collateral, and return to user
        if (_withdrawCollateral) {
            uint withdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);
    
            if (withdrawalAmount > 0) {
                IPool(AAVE_POOL).withdraw(baseToken, (withdrawalAmount / baseTokenConversion), user);
            }
        }
        
        // 5. If trade was profitable, pay user gains
        uint backingBaseAmountWei = (userPositions[_shortToken].backingBaseAmount - amountIn) * baseTokenConversion;
        uint gains = ReturnCapital.getPositionGains(_shortToken, baseToken, _percentageReduction, backingBaseAmountWei, debtAfterRepay);
        if (gains > 0) {
            IERC20(baseToken).transfer(msg.sender, gains / baseTokenConversion);
        }
        
        // 6. Update child contract's accounting
        userPositions[_shortToken].baseAmountsSwapped.push(amountIn);
        userPositions[_shortToken].shortTokenAmountsReceived.push(amountOut);
        userPositions[_shortToken].backingBaseAmount -= (amountIn + gains / baseTokenConversion);

        if (debtAfterRepay == 0) {
            userPositions[_shortToken].hasDebt = false;
        }
        
        return true;
    }


    /** 
    * @param _shortToken The address of the token that this function is attempting to obtain from Uniswap.
    * @param _positionReduction The amount that we're attempting to obtain from Uniswap (Units: short token decimals).
    * @return amountIn the amountIn to supply to uniswap when swapping to short tokens.
    **/
    function getAmountIn(uint _positionReduction, address _shortToken, uint _backingBaseAmount) private view returns (uint) {
        /// @dev Units: baseToken decimals
        uint priceOfShortTokenInBase = _shortToken.pricedIn(baseToken) / baseTokenConversion;  

        /// @dev Units: baseToken decimals = (baseToken decimals * shortToken decimals) / shortToken decimals
        uint positionReductionBase = (priceOfShortTokenInBase * _positionReduction) / (10 ** IwERC20(_shortToken).decimals());

        if (positionReductionBase <= _backingBaseAmount) {
            return positionReductionBase;
        } else {
            return _backingBaseAmount;
        }
    }

    /** 
    * @param _inputToken The address of the token that this function is attempting to give to Uniswap
    * @param _outputToken The address of the token that this function is attempting to obtain from Uniswap
    * @param _tokenInAmount The amount of the token, in WEI, that this function is attempting to give to Uniswap
    * @return amountIn The amount of tokens supplied to Uniswap for a desired token output amount
    * @return amountOut The amount of tokens received from Uniswap
    **/
    function swapExactInput(
        address _inputToken,
        address _outputToken,
        uint _tokenInAmount
    ) private returns (uint amountIn, uint amountOut) {

        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _tokenInAmount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _inputToken,
                tokenOut: _outputToken,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _tokenInAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        (amountIn, amountOut) = (_tokenInAmount, SWAP_ROUTER.exactInputSingle(params));
        emit SwapSuccess(msg.sender, _inputToken, amountIn, _outputToken, amountOut);
    }

    /** 
    * @param _outputToken The address of the token that this function is attempting to obtain from Uniswap
    * @param _inputToken The address of the token that this function is attempting to spend for output tokens.
    * @param _outputTokenAmount The amount this we're attempting to get from Uniswap (Units: shortToken decimals)
    * @param _inputMax The max amount of input tokens willing to spend (Units: baseToken decimals)
    * @return amountIn The amount of input tokens supplied to Uniswap (Units: baseToken decimals)
    * @return amountOut The amount of output tokens received from Uniswap (Units: shortToken decimals)
    **/
    function swapToShortToken(
        address _outputToken,
        address _inputToken,
        uint _outputTokenAmount,
        uint _inputMax
    ) private returns (uint amountIn, uint amountOut) {
        
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _inputMax);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: _inputToken,
                tokenOut: _outputToken,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: _outputTokenAmount,
                amountInMaximum: _inputMax,
                sqrtPriceLimitX96: 0
            });
        
        try SWAP_ROUTER.exactOutputSingle(params) returns (uint returnedAmountIn) {
            emit SwapSuccess(msg.sender, _inputToken, returnedAmountIn, _outputToken, _outputTokenAmount);
            (amountIn, amountOut) = (returnedAmountIn, _outputTokenAmount);

        } catch Error(string memory message) {
            emit ErrorString(message, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() instead.");
            amountIn = getAmountIn(_outputTokenAmount, _outputToken, _inputMax);
            (amountIn, amountOut) = swapExactInput(_inputToken, _outputToken, amountIn);

        } catch (bytes memory data) {
            emit LowLevelError(data, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() instead.");
            amountIn = getAmountIn(_outputTokenAmount, _outputToken, _inputMax);
            (amountIn, amountOut) = swapExactInput(_inputToken, _outputToken, amountIn);
        }
    }


    /** 
    * @dev  This function repays all child's outstanding (per asset) debt, in the case where all base token has been used already.
    * @param _shortToken The address of the token the user has shorted.
    * @param _paymentToken The address of the token used to repay outstanding debt (either base token or short token).
    * @param _paymentAmount The amount that's sent to repay the outstanding debt.
    * @param _withdrawCollateral A boolean to withdraw collateral or not.
    **/
    function payOutstandingDebt(address _shortToken, address _paymentToken, uint _paymentAmount, bool _withdrawCollateral) public userOnly returns (bool) {
        require(userPositions[_shortToken].backingBaseAmount == 0, "Position is still open.");
        require(_paymentToken == _shortToken || _paymentToken == baseToken, "Pay with short or base token.");
        
        // 1. Repay debt.
        if (_paymentToken == _shortToken) {
            // i. Transfer short tokens to this contract, so it can repay the Aave loan.
            IERC20(_shortToken).transferFrom(msg.sender, address(this), _paymentAmount);

            // ii. Repay Aave loan with the amount of short token supplied by the user.
            IERC20(_shortToken).approve(AAVE_POOL, _paymentAmount);
            IPool(AAVE_POOL).repay(_shortToken, _paymentAmount, 2, address(this));

        } else {
            // i. Transfer base tokens to this contract, so it can swap them for short tokens.
            IERC20(baseToken).transferFrom(msg.sender, address(this), _paymentAmount);

            // ii. Swap base tokens for short tokens, that will be used to repay the Aave loan.
            ( , uint amountOut) = swapExactInput(baseToken, _shortToken, _paymentAmount);


            // iii. Repay Aave loan with the amount of short tokens received from Uniswap.
            IERC20(_shortToken).approve(AAVE_POOL, amountOut);
            IPool(AAVE_POOL).repay(_shortToken, amountOut, 2, address(this));
        }

        // 2. Optionally withdraw collateral.
        if (_withdrawCollateral) {
            uint withdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);
            IPool(AAVE_POOL).withdraw(baseToken, withdrawalAmount, user);
        }

        // 3. Update accounting
        if (getOutstandingDebt(_shortToken) == 0) {
            userPositions[_shortToken].hasDebt = false;
        }

        return true;
    }

    /** 
    * @dev Returns this contract's total debt for a given short token (principle + interest).
    * @param _shortToken The address of the token the user has shorted.
    * @return outstandingDebt This contract's total debt for a given short token, in whatever decimals that short token has.
    **/
    function getOutstandingDebt(address _shortToken) public view userOnly returns (uint outstandingDebt) {
        address variableDebtTokenAddress = IPool(AAVE_POOL).getReserveData(_shortToken).variableDebtTokenAddress;
        outstandingDebt = IERC20(variableDebtTokenAddress).balanceOf(address(this));
    }


    /** 
    * @dev  This function returns the this contract's total debt, in terms of the base token (in Wei), for a given short token.
    * @param _shortToken The address of the token the user has shorted.
    * @return outstandingDebtBase This contract's total debt, in terms the base token (in Wei), for a given short token.
    **/
    function getOutstandingDebtBase(address _shortToken) public view userOnly returns (uint outstandingDebtBase) {
        uint priceOfShortTokenInBase = _shortToken.pricedIn(baseToken);                             // Wei
        uint totalShortTokenDebt = getOutstandingDebt(_shortToken);                                 // Wei
        outstandingDebtBase = (priceOfShortTokenInBase * totalShortTokenDebt).dividedBy(1e18, 0);   // Wei
    }


    /** 
    * @dev  This function returns a list of user's positions and their associated accounting data.
    * @return aggregatedPositionData A list of user's positions and their associated accounting data.
    **/
    function getAccountingData() external view userOnly returns (PositionData[] memory) {
        address[] memory _openedShortPositions = openedShortPositions; // Optimizes gas
        PositionData[] memory aggregatedPositionData = new PositionData[](_openedShortPositions.length);
        for (uint i = 0; i < _openedShortPositions.length; i++) {
            PositionData storage position = userPositions[_openedShortPositions[i]];
            aggregatedPositionData[i] = position;
        }
        return aggregatedPositionData;
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
    **/
    function getAaveAccountData() public view userOnly returns (uint totalCollateralBase, uint totalDebtBase, uint availableBorrowBase, uint currentLiquidationThreshold, uint ltv, uint healthFactor, uint maxWithdrawalAmount) {
        maxWithdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);
        (totalCollateralBase, totalDebtBase, availableBorrowBase, currentLiquidationThreshold, ltv, healthFactor) = IPool(AAVE_POOL).getUserAccountData(address(this));   // Must multiply by 1e10 to get Wei
    }

    /** 
    * @dev  This function allows a user to withdraw collateral on their Aave account, up to an
            amount that does not raise their debt-to-collateral ratio above 70%.
    * @param _withdrawAmount The amount of collateral (in Wei) the user wants to withdraw.
    **/
    function withdrawCollateral(uint _withdrawAmount) public userOnly {
        uint maxWithdrawalAmount = ReturnCapital.getMaxWithdrawal(address(this), shaaveLTV);

        require(_withdrawAmount <= maxWithdrawalAmount, "Exceeds max withdrawal amount.");

        IPool(AAVE_POOL).withdraw(baseToken, _withdrawAmount, user);
    }

    modifier userOnly() {
        require(msg.sender == user, "Unauthorized.");
        _;
    }
}







