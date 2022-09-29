// contracts/Aave.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// import "https://github.com/aave/aave-v3-core/blob/master/contracts/interfaces/IPool.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract Aave {

    // Storage Variables
    address public borrowTokenAddress = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464; // Goerli Aave DAI
    address public supplyTokenAddress = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43; // Goerli Aave USDC
    address public aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;    // Goerli Aave Pool Address


    constructor() {}
    
    function supply() public returns (bool) {
        // 1. Set amountToDrain to the contract's supplyTokenAddress balance
        uint amountToDrain = IERC20(supplyTokenAddress).balanceOf(address(this));

        // 2. Approve Aave pool to access amountToDrain from this contract 
        IERC20(supplyTokenAddress).approve(aavePoolAddress, amountToDrain);

        // 3. Supply amountToDrain to Aave pool
        IPool(aavePoolAddress).supply(supplyTokenAddress, amountToDrain, address(this), 0);

        return true;
    }

    function borrow() public returns (bool) {
        // Borrow 0.3 DAI
        IPool(aavePoolAddress).borrow(borrowTokenAddress, 0.3 ether, 2, 0, address(this));

        return true;
    }

    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

// Full successful supply-borrow test on the below contract
// 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464