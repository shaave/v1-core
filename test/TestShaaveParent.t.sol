// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Local Imports
import "../src/contracts/ShaaveParent.sol";
import "../src/interfaces/IShaaveChild.sol";
import "./Mocks/MockAavePool.t.sol";

// External Package Imports
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TestShaaveParentData is Test {

    // Contracts
    ShaaveParent shaaveParent;
    MockAavePool mockAavePool;

    // Test Events
    event CollateralSuccess(address user, address testBaseTokenAddress , uint amount);

    function setUp() public {
        shaaveParent = new ShaaveParent();
        mockAavePool = new MockAavePool();
    }

    function test_getNeededCollateralAmount() public {

        // Test Variables
        address testAaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB; // Goerli Aave Pricing Oracle Address
        address testShortTokenAddress = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464; // Goerli Aaave DAI
        address testBaseTokenAddress  = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43; // Goerli Aaave USDC
        uint    testShortTokenAmount  = 15e18;                                         // Amount of short token desired
        uint    inputTokenPriceUSD    = 10e8;                                       // input token price in USD
        uint    baseTokenPriceUSD     = 1e8;                                        // base currency token price in USD
    

        // Mocks
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, testShortTokenAddress),
            abi.encode(inputTokenPriceUSD)
        );
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, testBaseTokenAddress),
            abi.encode(baseTokenPriceUSD)
        );

        // Act
        uint testCollateralAmount = shaaveParent.getNeededCollateralAmount(testShortTokenAddress, testShortTokenAmount);

        // Assertions
        assertEq(testCollateralAmount, 214285714285714285700);
    }

    function test_getNeededCollateralAmountZeroAddress() public {
        // Act
        vm.expectRevert("_shortTokenAddress must be a nonzero address.");
        shaaveParent.getNeededCollateralAmount(address(0), 15);
    }

    function test_getNeededCollateralAmountInvalidAmount() public {
        // Act
        vm.expectRevert("_shortTokenAmount must be greater than zero.");
        address testShortTokenAddress = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464; // Goerli Aaave DAI
        shaaveParent.getNeededCollateralAmount(testShortTokenAddress, 0);
    }

}