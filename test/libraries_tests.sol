// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@aave-protocol/interfaces/IAaveOracle.sol";
import "../src/contracts/libraries/ShaavePricing.sol";


contract TestShaavePricing is Test {

    function testAaveOracle() public {

        // Test Variables
        address testAaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB; // Goerli Aave Pricing Oracle Address
        address shortTokenAddress     = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464; // Goerli Aaave DAI
        address baseTokenAddress      = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43; // Goerli Aaave USDC
        uint price;                                                                 // price in wei

        // Arrange
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, shortTokenAddress),
            abi.encode(10e8)
        );
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, baseTokenAddress),
            abi.encode(1e8)
        );

        // Act
        price = ShaavePricing.pricedIn(shortTokenAddress, baseTokenAddress);
        
        // Assert
        assertEq(price, 10e18);
    }
}