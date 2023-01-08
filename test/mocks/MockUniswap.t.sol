// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// External packages
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

// Local file imports
import "../common/constants.t.sol";

contract MockUniswapGains {
    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata params)
        public
        payable
        returns (uint256 amountIn)
    {
        amountIn = UNISWAP_AMOUNT_IN_PROFIT;
        TransferHelper.safeTransferFrom(params.tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeTransfer(SHORT_TOKEN, msg.sender, IERC20(SHORT_TOKEN).balanceOf(address(this)));
    }
}

contract MockUniswapLosses {
    function exactOutputSingle() public pure {
        revert("Mocking a failure here.");
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        public
        payable
        returns (uint256 amountOut)
    {
        amountOut = IERC20(SHORT_TOKEN).balanceOf(address(this));
        TransferHelper.safeTransferFrom(params.tokenIn, msg.sender, address(this), params.amountIn);
        TransferHelper.safeTransfer(SHORT_TOKEN, msg.sender, amountOut);
    }
}
