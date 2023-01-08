// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import "@aave-protocol/interfaces/IPool.sol";

import "../../src/parent/Parent.sol";
import "solmate/utils/SafeTransferLib.sol";
import "../../src/libraries/AddressArray.sol";
import "../../src/interfaces/IChild.sol";
import "../common/constants.t.sol";

contract ShortTest is Test {
    using AddressArray for address[];

    address[] BANNED_COLLATERAL = [
        0xE0B52e49357Fd4DAf2c15e02058DCE6BC0057db4,
        0xE111178A87A3BFf0c8d18DECBa5798827539Ae99,
        0x4e3Decbb3645551B8A19f0eA1678079FCB33fB4c,
        0xa3Fa99A148fA48D14Ed51d610c367C61876997F1,
        0xc2132D05D31c914a87C6611C10748AEb04B58e8F,
        0x172370d5Cd63279eFa6d502DAB29171933a610AF,
        0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a,
        0x385Eeac5cB85A38A9a07A70c73e0a3271CfB54A7,
        0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3,
        0x85955046DF4668e1DD369D2DE9f3AEB98DD2A369,
        0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6,
        0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4
    ];

    address[] children;
    address[] baseTokens;

    // Contracts
    Parent shaaveParent;

    function setUp() public {
        shaaveParent = new Parent(10);
    }

    function test_addShortPosition() public {
        // Setup
        uint256 amountMultiplier = 1;

        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        uint256 childrenCount;
        for (uint256 i = 0; i < reserves.length; i++) {
            if (!BANNED_COLLATERAL.includes(reserves[i])) {
                if (reserves[i] != SHORT_TOKEN) {
                    // Setup
                    uint256 baseTokenAmount = (10 ** IERC20Metadata(reserves[i]).decimals()) * amountMultiplier; // 1 unit in correct decimals
                    deal(reserves[i], address(this), baseTokenAmount);
                    SafeTransferLib.safeApprove(ERC20(reserves[i]), address(shaaveParent), baseTokenAmount);

                    // Expectations
                    address[] memory childContracts = shaaveParent.retreiveChildrenByUser();
                    uint256 nonZeroAddressCount;
                    for (uint256 j = 0; j < childContracts.length; j++) {
                        if (childContracts[j] != address(0)) {
                            baseTokens.push(IChild(childContracts[j]).baseToken());
                            nonZeroAddressCount++;
                        }
                    }

                    uint256 preActionChildCount = nonZeroAddressCount;
                    assertEq(preActionChildCount, childrenCount, "preAction count off");
                    assert(!baseTokens.includes(reserves[i]));

                    // Act
                    shaaveParent.addShortPosition(SHORT_TOKEN, reserves[i], baseTokenAmount);

                    // Post-action data extraction
                    childContracts = shaaveParent.retreiveChildrenByUser();

                    // Assertions
                    delete baseTokens;
                    nonZeroAddressCount = 0;
                    for (uint256 k = 0; k < childContracts.length; k++) {
                        if (childContracts[k] != address(0)) {
                            baseTokens.push(IChild(childContracts[k]).baseToken());
                            nonZeroAddressCount++;
                        }
                    }
                    assertEq(nonZeroAddressCount, preActionChildCount + 1, "postAction count off");
                    assert(baseTokens.includes(reserves[i]));

                    childrenCount++;
                }
            }
        }
    }
}
