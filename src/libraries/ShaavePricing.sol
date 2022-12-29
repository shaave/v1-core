// contracts/libraries/ShaavePricing.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// External Package Imports
import "@aave-protocol/interfaces/IAaveOracle.sol";
import "./Math.sol";

/**
 * @title ShaavePricing library
 * @author shAave
 * @dev Implements the logic related to asset pricing.
*/
library ShaavePricing {

    using Math for uint;

    address constant aaveOracleAddress = 0xb023e699F5a33916Ea823A16485e259257cA8Bd1;  // Polygon

    function pricedIn(address _inputTokenAddress, address _baseTokenAddress) internal view returns (uint assetPriceInBase) {
        uint inputTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_inputTokenAddress);
        uint baseTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_baseTokenAddress);
        assetPriceInBase = inputTokenPriceUSD.dividedBy(baseTokenPriceUSD, 18);       // Wei
    }
}