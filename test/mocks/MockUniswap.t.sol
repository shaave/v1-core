// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// External packages
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

// Local file imports
import "../common/constants.t.sol";


import "forge-std/console.sol";

contract MockUniswap {
    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata params) public payable returns (uint256 amountIn) {
        amountIn = UNISWAP_AMOUNT_IN_PROFIT;
        TransferHelper.safeTransferFrom(params.tokenIn, msg.sender, address(this), UNISWAP_AMOUNT_IN_PROFIT);
        console.log("[Mock]: Just transfered:", amountIn, "USDC");
        TransferHelper.safeTransfer(SHORT_TOKEN, msg.sender, IERC20(SHORT_TOKEN).balanceOf(address(this)));
    }
}

