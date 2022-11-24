// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@uniswap-v3-periphery/libraries/TransferHelper.sol";

interface IwERC20 is IERC20 {
    function decimals() external view returns (uint8);
}   