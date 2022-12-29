// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// External Package Imports
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

// Local imports
import "../interfaces/IERC20Metadata.sol";
import "../libraries/ShaavePricing.sol";


abstract contract SwapService {
    using ShaavePricing for address;

    // Constants
    uint24 public constant POOL_FEE = 3000;
    ISwapRouter public constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // Event
    event SwapSuccess(address user, address tokenInAddress, uint tokenInAmount, address tokenOutAddress, uint tokenOutAmount);
    event ErrorString(string errorMessage, string executionInsight);
    event LowLevelError(bytes errorData, string executionInsight);

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
    ) internal returns (uint amountIn, uint amountOut) {

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
        uint _inputMax,
        uint _baseTokenConversion
    ) internal returns (uint amountIn, uint amountOut) {
        
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
            amountIn = getAmountIn(_outputToken, _inputToken, _baseTokenConversion, _outputTokenAmount, _inputMax);
            (amountIn, amountOut) = swapExactInput(_inputToken, _outputToken, amountIn);

        } catch (bytes memory data) {
            emit LowLevelError(data, "Uniswap's exactOutputSingle() failed. Trying exactInputSingle() instead.");
            amountIn = getAmountIn(_outputToken, _inputToken, _baseTokenConversion, _outputTokenAmount, _inputMax);
            (amountIn, amountOut) = swapExactInput(_inputToken, _outputToken, amountIn);
        }
    }

    /** 
    * @param _shortToken The address of the token that this function is attempting to obtain from Uniswap.
    * @param _positionReduction The amount that we're attempting to obtain from Uniswap (Units: short token decimals).
    * @return amountIn the amountIn to supply to uniswap when swapping to short tokens.
    **/
    function getAmountIn(address _shortToken, address _baseToken, uint _baseTokenConversion, uint _positionReduction,  uint _backingBaseAmount) internal view returns (uint) {
        /// @dev Units: baseToken decimals
        uint priceOfShortTokenInBase = _shortToken.pricedIn(_baseToken) / _baseTokenConversion;  

        /// @dev Units: baseToken decimals = (baseToken decimals * shortToken decimals) / shortToken decimals
        uint positionReductionBase = (priceOfShortTokenInBase * _positionReduction) / (10 ** IERC20Metadata(_shortToken).decimals());

        if (positionReductionBase <= _backingBaseAmount) {
            return positionReductionBase;
        } else {
            return _backingBaseAmount;
        }
    }
}