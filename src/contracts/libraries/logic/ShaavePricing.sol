// contracts/ShaavePricing.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// External Package Imports
import "@aave-protocol/interfaces/IAaveOracle.sol";


/**
 * @title ShaavePricing library
 * @author Shaave
 * @dev Implements the logic related to asset pricing.
*/
library ShaavePricing {

    address constant aaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;

    function getAssetPriceInBase(address _baseTokenAddress, address _inputTokenAddress) internal view returns (uint assetPriceInBase) {
        uint inputTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_inputTokenAddress);
        uint baseTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_baseTokenAddress);
        assetPriceInBase = (inputTokenPriceUSD / baseTokenPriceUSD) * 1e18;  // TODO: Doesn't work
    }
}