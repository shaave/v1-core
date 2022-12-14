// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Local imports
import "forge-std/Test.sol";
import "../../src/libraries/MathLib.sol";
import "../../src/libraries/PricingLib.sol";
import "../common/Constants.t.sol";

// External package imports
import "@aave-protocol/interfaces/IAaveOracle.sol";

contract ShaavePricingTest is Test {
    using PricingLib for address;
    using MathLib for uint256;

    function test_pricedIn() public {
        // Expectations
        uint256 inputTokenPriceUSD = IAaveOracle(AAVE_ORACLE).getAssetPrice(SHORT_TOKEN);
        uint256 baseTokenPriceUSD = IAaveOracle(AAVE_ORACLE).getAssetPrice(BASE_TOKEN);
        uint256 expectedAssetPriceInBase = inputTokenPriceUSD.dividedBy(baseTokenPriceUSD, 18);

        // Act
        uint256 assetPriceInBase = SHORT_TOKEN.pricedIn(BASE_TOKEN);

        // Assertions
        assertEq(assetPriceInBase, expectedAssetPriceInBase);
    }
}
