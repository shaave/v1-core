// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/contracts/ShaaveParent.sol";
import "../src/interfaces/IShaaveChild.sol";
import "./Mocks/MockAavePool.t.sol";

import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


// contract Admin {
//     receive() external payable {}
// }

contract TestShaaveParentData is Test {

    // Contracts
    ShaaveParent shaaveParent;
    MockAavePool mockAavePool;
    // Admin admin;

    // Test Variables
    address testUser1 = 0x535d25c5cb10fc36656b3288C40fD4248aE5817d;
    address testChild1 = 0x3FA24585271Bf1Ab7D603f378fE64Bd728C8bD25;
    address testUser2 = 0x22BcD8Fb0b0508E914BaCB5182Fba6264ccA7e45;
    address testChild2 = 0x2C10a6FcaD5bd6c671d8cFDB53D8968d1f9E3A99;

    // Test Events
    event CollateralSuccess(address user, address baseTokenAddress, uint amount);

    function setUp() public {
        // admin = new Admin();
        shaaveParent = new ShaaveParent();
        mockAavePool = new MockAavePool();
    }

    function testFunction1() public {
        address aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;

        bytes memory code = address(mockAavePool).code;
        address targetAddr = aavePoolAddress;
        vm.etch(targetAddr, code);

        vm.mockCall(
            aavePoolAddress,
            abi.encodeWithSelector(IPool(aavePoolAddress).supply.selector),
            abi.encode(true)
        );

        bool response = shaaveParent.function3();

        assertTrue(response);
    }
}