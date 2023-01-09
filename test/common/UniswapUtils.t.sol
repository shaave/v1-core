// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Foundry
import "forge-std/Test.sol";

// External packages
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

// Local file imports
import "../../src/libraries/PricingLib.sol";
import "../../src/interfaces/IERC20Metadata.sol";
import "./Constants.t.sol";

contract UniswapUtils is Test {
    using PricingLib for address;

    /// @dev This is a test function for computing expected results
    function swapExactInput(address _inputToken, address _outputToken, uint256 _tokenInAmount)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        deal(SHORT_TOKEN, address(this), _tokenInAmount);

        ISwapRouter SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _tokenInAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _inputToken,
            tokenOut: _outputToken,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _tokenInAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        (amountIn, amountOut) = (_tokenInAmount, SWAP_ROUTER.exactInputSingle(params));

        // Revert to previous snapshot, as if swap never happend
        vm.revertTo(id);
    }

    /// @dev This is a test function for computing expected results
    function swapToShortToken(
        address _outputToken,
        address _inputToken,
        uint256 _outputTokenAmount,
        uint256 _inputMax,
        uint256 baseTokenConversion
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        /// Take snapshot of blockchain state
        uint256 id = vm.snapshot();

        // Give this contract (positionBackingBaseAmount) base tokens
        deal(BASE_TOKEN, address(this), _inputMax);

        ISwapRouter SWAP_ROUTER = ISwapRouter(UNISWAP_SWAP_ROUTER);
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _inputMax);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _inputToken,
            tokenOut: _outputToken,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _outputTokenAmount,
            amountInMaximum: _inputMax,
            sqrtPriceLimitX96: 0
        });

        try SWAP_ROUTER.exactOutputSingle(params) returns (uint256 returnedAmountIn) {
            (amountIn, amountOut) = (returnedAmountIn, _outputTokenAmount);
        } catch {
            amountIn = getAmountIn(_outputTokenAmount, _outputToken, _inputMax, baseTokenConversion);
            (amountIn, amountOut) = swapExactInput(_inputToken, _outputToken, amountIn);
        }

        // Revert to previous snapshot, as if swap never happend
        vm.revertTo(id);
    }

    /// @dev This is a test function for computing expected results
    function getAmountIn(
        uint256 _positionReduction,
        address _shortToken,
        uint256 _backingBaseAmount,
        uint256 baseTokenConversion
    ) internal view returns (uint256) {
        /// @dev Units: baseToken decimals
        uint256 priceOfShortTokenInBase = _shortToken.pricedIn(BASE_TOKEN) / baseTokenConversion;

        /// @dev Units: baseToken decimals = (baseToken decimals * shortToken decimals) / shortToken decimals
        uint256 positionReductionBase =
            (priceOfShortTokenInBase * _positionReduction) / (10 ** IERC20Metadata(_shortToken).decimals());

        if (positionReductionBase <= _backingBaseAmount) {
            return positionReductionBase;
        } else {
            return _backingBaseAmount;
        }
    }
}
