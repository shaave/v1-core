// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/contracts/libraries/Math.sol";
import "../../src/contracts/libraries/ShaavePricing.sol";

contract Test_ShaavePricing is Test {
    using ShaavePricing for address;
    using Math for uint;

    /*******************************************************************************
    **
    **  pricedIn tests
    **
    *******************************************************************************/

    function test_pricedIn() public {

        // Arrange
        address testAaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB; // Goerli Aave Pricing Oracle Address
        address shortTokenAddress     = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464; // Goerli Aaave DAI
        address baseTokenAddress      = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43; // Goerli Aaave USDC
        uint    inputTokenPriceUSD    = 10e8;                                       // input token in base currency
        uint    baseTokenPriceUSD     = 1e8;                                        // base token in base currency
        uint    assetPriceInBase;                                                   // price of shortToken in baseToken expressed in Wei

        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, shortTokenAddress),
            abi.encode(inputTokenPriceUSD)
        );
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, baseTokenAddress),
            abi.encode(baseTokenPriceUSD)
        );

        // Act
        assetPriceInBase = shortTokenAddress.pricedIn(baseTokenAddress);

        // Assert
        assertEq(assetPriceInBase, inputTokenPriceUSD.dividedBy(baseTokenPriceUSD, 0) * 1 ether);
    }
}