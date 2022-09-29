/* NOTE: This contract is merely for reference, it will NOT be used. Only including, as it has
some sample code, which is salvageable.
*/


// contracts/ShortStop.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

import "@aave-protocol/interfaces/IPool.sol";
import "@aave-protocol/interfaces/IAaveOracle.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

contract Shaave {

    // Storage Variables
    struct PositionData {
        uint[] shortTokenAmountsSwapped;
        uint[] usdcAmountsReceived;
        uint[] collateralAmounts;
        uint[] usdcAmountsSwapped;
        uint[] shortTokenAmountsReceived;
        uint totalUsdc;        // NOTE: This should be ADDED to and SUBTRACTED from
        uint totalShortToken;  // NOTE: This should be ADDED to and SUBTRACTED from
    }

    mapping(address => mapping(address => PositionData)) public userPositions;
    address admin;

    // -- Aave Variables --
    address public collateralTokenAddress = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;    // Goerli Aave USDC
    address public aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;           // Goerli Aave Pool Address
    address public aaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;         // Goerli Aave Oracle Address
    // -- Uniswap Variables --
    uint24 public constant poolFee = 3000;
    ISwapRouter public immutable swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;  // Goerli
    uint public swapBuffer = 1;


    // Events
    event CollateralSuccess(address user, address shortTokenAddress, uint amount);
    event BorrowSuccess(address borrowTokenAddress, uint amount);
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);
    event PositionAddedSuccess(address user, address shortTokenAddress, uint amount);
    event ErrorString(string errorMessage, string executionInsight);
    event LowLevelError(bytes errorData, string executionInsight);


    constructor() {
        admin = payable(msg.sender);
    }

    function addShortPosition(
        address _shortTokenAddress,
        uint _shortTokenAmount,
        uint _collateralTokenAmount
    ) public returns (bool) {

        // TODO: If it's possible to validation here, do it.
        require(_shortTokenAmount > 0, "_shortTokenAmount must be a positive value.");
        require(_collateralTokenAmount > 0, "_shortTokenAmount must be a positive value.");
        require(_shortTokenAddress != address(0), "_shortTokenAddress must be a nonzero address.");
        
        // 1. Borrow asset
        borrowAsset(_shortTokenAddress, _shortTokenAmount, _collateralTokenAmount);
        // 2. Swap borrowed asset for dollars
        uint amountOut = swapExactInput(_shortTokenAddress, collateralTokenAddress, _shortTokenAmount);
        // 3. Emit event, notifying that a position was added to
        emit PositionAddedSuccess(msg.sender, _shortTokenAddress, _shortTokenAmount);

        // 4. Update user's accounting
        userPositions[msg.sender][_shortTokenAddress].shortTokenAmountsSwapped.push(_shortTokenAmount);
        userPositions[msg.sender][_shortTokenAddress].usdcAmountsReceived.push(amountOut);
        userPositions[msg.sender][_shortTokenAddress].collateralAmounts.push(_collateralTokenAmount);
        userPositions[msg.sender][_shortTokenAddress].totalUsdc += amountOut;
    }

    function borrowAsset(address _shortTokenAddress, uint _shortTokenAmount, uint _collateralTokenAmount) internal returns (bool) {  //TODO: Do we need returns (bool) here?
        
        // 1. Transfer the user's collateral amount to this contract, so it can initiate a loan
        IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), _collateralTokenAmount);

        // 2. Approve Aave to handle collateral on this contract's behalf
        IERC20(collateralTokenAddress).approve(aavePoolAddress, _collateralTokenAmount);
        
        // 3. Supply collateral to Aave, which grants this contract the ability to borrow assets
        IPool(aavePoolAddress).supply(collateralTokenAddress, _collateralTokenAmount, msg.sender, 0);
        emit CollateralSuccess(msg.sender, _collateralTokenAmount);

        // 4. Borrow asset from Aave on user's behalf
        IPool(aavePoolAddress).borrow(_shortTokenAddress, _shortTokenAmount, 2, 0, msg.sender);
        emit BorrowSuccess(msg.sender, _shortTokenAddress, _shortTokenAmount);
    }

    function reducePosition(address _shortTokenAddress, uint _percentageReduction) public returns (bool) {
        require(_percentageReduction > 100, "Percentage cannot exceed 100.");
        //TODO: Require that we have accounting for this user first (user exists AND posisition exists)



        // 1. Fetch debtToken address
        address variableDebtTokenAddress = IPool(aavePoolAddress).getReserveData(_shortTokenAddress)[10];

        // 2. Fetch msg.sender's debtToken balance. This value represents what the user owes (principle + interest)
        uint userDebtAmount = IERC20(variableDebtTokenAddress).balanceOf(msg.sender);

        // 3. Obtain user's short token posisition's backed USDC value held by this contract
        uint userPosisitionTotalUsdc = userPositions[msg.sender][_tokenOutAddress].totalUsdc; 
        
        if (_percentageReduction == 100) {
            // 3. Swap from USDC to short token
            (uint amount, uint amountType) = swapToShortToken(_shortTokenAddress, userDebtAmount, userPosisitionTotalUsdc);
        } else {
            uint amountShortTokenToSwap = (userDebtAmount * _percentageReduction) / 100;            // FIXME: NEED TO SCALE THIS VALUE
            uint assetPrice = IAaveOracle(aaveOracleAddress).getAssetPrice(_shortTokenAddress);
            uint amountShortTokenInUsdc = amountShortTokenToSwap * assetPrice;
            uint bufferedAmountIn = (amountShortTokenInUsdc * (100 + swapBuffer)) / 100;            // FIXME: NEED TO SCALE THIS VALUE
            (uint amount, uint amountType) = swapToShortToken(_shortTokenAddress, amountShortTokenToSwap, bufferedAmountIn);
        }

        // If I'm reducing my position by 10%, that should be the amount of short token by 10%, not USDC backing the position
        // How to get that? Get the total amount owed by user, then multiple that by percentage, then output swap for that under the exact same logic as the above 

        if (amountType == 0) {
            // NOTE: This only happens if the short position actually made money
            // 1. Update user's accounting
            userPositions[msg.sender][_shortTokenAddress].totalUsdc -= amount;
            userPositions[msg.sender][_shortTokenAddress].usdcAmountsSwapped.push(amount);
            userPositions[msg.sender][_shortTokenAddress].shortTokenAmountsReceived.push(userDebtAmount);
            // 2. Repay Aave userDebtAmount
            IPool(aavePoolAddress).repay(_shortTokenAddress, userDebtAmount, 2, msg.sender);
            // 3. Repay user the net amount of USDC that their short trade made
            // 4. Withdraw the maximum amount of collateral from Aave on behalf of the user
        } else {
            // NOTE: Possible cases [1]: user sold part of the position [2]: User sold all, but the short trade actually LOST money
            if (_percentageReduction == 100) {
                // NOTE: case [2]: User lost money on their trade and doesn't have enough to repay Aave, but has swapped all of his USDC
                // 1. Update user's accounting 
                userPositions[msg.sender][_shortTokenAddress].totalUsdc -= userPosisitionTotalUsdc;
                userPositions[msg.sender][_shortTokenAddress].usdcAmountsSwapped.push(userPosisitionTotalUsdc);
                userPositions[msg.sender][_shortTokenAddress].shortTokenAmountsReceived.push(amount);

                // 2. Repay Aave an amount less than what is owed
                IPool(aavePoolAddress).repay(_shortTokenAddress, amount, 2, msg.sender);

                // 3. There will be no USDC left over to pay user, so withdraw the maximum amount of collateral possible from Aave on behalf of the user
                // 4. TODO: There should be a way for the user to know if they still owe aave or not... That can frontend thing... or a backend thing
            } else {
                // NOTE: case [1]: User just sold a portion of their posisition
                // 1. Update user's accounting 
                userPositions[msg.sender][_shortTokenAddress].totalUsdc -= amountUsdcToSwap;
                userPositions[msg.sender][_shortTokenAddress].usdcAmountsSwapped.push(amountUsdcToSwap);
                userPositions[msg.sender][_shortTokenAddress].shortTokenAmountsReceived.push(amount);

                // 2. Repay Aave whatever shortToken we just received
                IPool(aavePoolAddress).repay(_shortTokenAddress, amount, 2, msg.sender);

                // 3. Repay user percentage of USD. How to calculate?
                // If you're down on the position, you get NO USDC.
                // If you're up on the the position, how much are you up by?
                // The amount you owe (in USDC) - the amount of USDC you HAVE in this contract for that position = delta dollars
                // percentage * delta dollars ==> pay that to the user

            }

        }
    }

    
    /** 
    * @param _tokenOutAddress The address of the token that this function is attempting to obtain from Uniswap
    * @param _tokenOutAmount The amount of the token, in WEI, that this function is attempting to obtain from Uniswap
    * @return amount The amount returned from Uniswap (this can be an amountIn or amountOut, denoted by amountType)
    * @return amountType The type of amount (0 = amountIn, 1 = amountOut) 
    **/
    function swapToShortToken(address _tokenOutAddress, uint _tokenOutAmount, uint _amountInMaxium) internal returns (uint amount, uint amountType) {
        
        TransferHelper.safeApprove(collateralTokenAddress, address(swapRouter), _amountInMaxium);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: collateralTokenAddress,
                tokenOut: _tokenOutAddress,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: _tokenOutAmount,
                amountInMaximum: _amountInMaxium,
                sqrtPriceLimitX96: 0
            });
        
        try swapRouter.exactOutputSingle(params) returns (uint amount) {
            emit SwapSuccess(msg.sender, collateralTokenAddress, amountIn, _tokenOutAddress, _tokenOutAmount);
            return (amount, 0);
        } catch Error(string memory reason) {
            emit LogErrorString(reason, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() now.");
            return swapExactInput(collateralTokenAddress, _tokenOutAddress, _amountInMaxium);
        } catch (bytes memory reason) {
            emit LowLevelError(reason, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() now.");
            return swapExactInput(collateralTokenAddress, _tokenOutAddress, _amountInMaxium);
        }
    }


    /** 
    * @param _tokenInAddress The address of the token that this function is attempting to give to Uniswap
    * @param _tokenOutAddress The address of the token that this function is attempting to obtain from Uniswap
    * @param _tokenInAmount The amount of the token, in WEI, that this function is attempting to give to Uniswap
    * @return amount The amount returned from Uniswap (this can be an amountIn or amountOut, denoted by amountType)
    * @return amountType The type of amount (0 = amountIn, 1 = amountOut) 
    **/
    function swapExactInput(address _tokenInAddress, address _tokenOutAddress, uint _tokenInAmount) internal returns (uint amount, uint amountType) {

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

        (amount, amountType) = (swapRouter.exactInputSingle(params), 1);
        emit SwapSuccess(msg.sender, _tokenInAddress, _tokenInAmount, _tokenOutAddress, amountOut);
    }

    
    function getNeededCollateralAmount(
        address _collateralTokenAddress,
        address _shortTokenAddress,
        uint _shortTokenAmount
    ) public pure returns (uint) {
        // TODO: This will be used for other collateral tokens; need LTV for that
        uint assetPrice = IAaveOracle(aaveOracleAddress).getAssetPrice(_shortTokenAddress);
        uint amountShortTokenCost = _shortTokenAmount * assetPrice;
        return (amountShortTokenCost / .70) * 1e18;                      // FIXME: NEED TO SCALE THIS VALUE
    }

    modifier adminOnly() {
        require(msg.sender == admin);
        _;
    }

}






