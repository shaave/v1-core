// contracts/TokenSwap.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

// import "https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/ISwapRouter.sol";
// import "https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/TransferHelper.sol";
import "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

contract TokenSwap {

    // Storage Variables
    uint24 public constant poolFee = 3000;                                           // 0.3%
    address public tokenGiveAddress = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;    // Goerli UNI
    address public tokenReceiveAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6; // Goerli Uniswap WETH
    ISwapRouter public immutable swapRouter;                                         // SwapRouter interface

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;  // 0xE592427A0AEce92De3Edee1F18E0157C05861564
    } 

    // Swap from matic to weth
    function swapToWeth() public returns (bool) {
        // 1. Set amountToSwap to the contract's supplyTokenAddress balance
        uint amountToSwap = IERC20(tokenGiveAddress).balanceOf(address(this));

        // 2. Approve Uniswap to access amountToSwap from this contract
        TransferHelper.safeApprove(tokenGiveAddress, address(swapRouter), amountToSwap);

        // 3. Construct swap params
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenGiveAddress,
                tokenOut: tokenReceiveAddress,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // 4. Execute token swap
        swapRouter.exactInputSingle(params);

        return true;
    }

    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

// Full successful swap test on the below contract
// 0xE1d9c063Bd258C4EEC34a9e872e33c7626473AAb