// contracts/SuperFluid.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// import "https://github.com/superfluid-finance/protocol-monorepo/blob/dev/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
// import "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

// contract SuperFluid {

//     // Storage Variables
//     ISuperToken fDAIx = ISuperToken(0xF2d68898557cCb2Cf4C10c3Ef2B034b2a69DAD00);  //Goerli fDAIx

//     constructor() {}

//     function convertTofDAI() public returns (bool) {
//          // 1. Store in variable the amount of fDAIx in contract
//         uint amountToDowngrade = fDAIx.balanceOf(address(this));

//         // 2. Ensure that the contract has a nonzero fDAIx balance
//         require(amountToDowngrade > 0, "This contract does not have fDAIx.");

//         // 3. Downgrade (unwrap) that amount of fDAIx in the contract to fDAI
//         fDAIx.downgrade(amountToDowngrade);

//         return true;
//     }
// }

// Full successful stream-downgrade test on the below contract
// 0x11A773a48C78f84AE8871bDBc8284346e1F60194