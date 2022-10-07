// contracts/libraries/ShaavePricing.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

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

    address constant aaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;  // Goerli Aave Pricing Oracle Address

    function pricedIn(address _inputTokenAddress, address _baseTokenAddress) internal view returns (uint assetPriceInBase) {
        uint inputTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_inputTokenAddress);
        uint baseTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_baseTokenAddress);
        assetPriceInBase = inputTokenPriceUSD.dividedBy(baseTokenPriceUSD, 18);       // Wei
    }
}