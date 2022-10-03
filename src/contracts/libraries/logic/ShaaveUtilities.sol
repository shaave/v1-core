// contracts/ShortStop.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// External Package Imports
import "@aave-protocol/interfaces/IAaveOracle.sol";


/**
 * @title ShaaveUtilities library
 * @author Shaave
 * @dev Implements the logic for ShaaveChild-specific functions
*/
library ShaaveUtilities {

    address constant aaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;

    function getAssetPriceInBase(address _baseTokenAddress, address _inputTokenAddress) internal view returns (uint assetPriceInBase) {
        uint inputTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_inputTokenAddress);
        uint baseTokenPriceUSD = IAaveOracle(aaveOracleAddress).getAssetPrice(_baseTokenAddress);
        assetPriceInBase = inputTokenPriceUSD / baseTokenPriceUSD;
    }
}