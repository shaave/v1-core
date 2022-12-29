// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Local imports
import "forge-std/Test.sol";
import "../../src/libraries/Math.sol";
import "../../src/libraries/ShaavePricing.sol";
import "../common/constants.t.sol";

// External package imports
import "@aave-protocol/interfaces/IAaveOracle.sol";

contract ShaavePricingTest is Test {
    using ShaavePricing for address;
    using Math for uint;

    function test_pricedIn() public {
        // Expectations
        uint inputTokenPriceUSD = IAaveOracle(AAVE_ORACLE).getAssetPrice(SHORT_TOKEN);
        uint baseTokenPriceUSD = IAaveOracle(AAVE_ORACLE).getAssetPrice(BASE_TOKEN);
        uint expectedAssetPriceInBase = inputTokenPriceUSD.dividedBy(baseTokenPriceUSD, 18);  

        // Act
        uint assetPriceInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN);

        // Assertions
        assertEq(assetPriceInBase, expectedAssetPriceInBase);
    }
}