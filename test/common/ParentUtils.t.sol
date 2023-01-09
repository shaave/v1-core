// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@aave-protocol/interfaces/IPool.sol";
import "../../src/interfaces/IERC20Metadata.sol";
import "../../src/libraries/PricingLib.sol";
import "../../src/libraries/MathLib.sol";

import "./Constants.t.sol";

contract ParentUtils {
    using PricingLib for address;
    using MathLib for uint256;

    function expectedCollateralAmount(address _shortToken, address _baseToken, uint256 _shortTokenAmount)
        internal
        view
        returns (uint256)
    {
        uint256 shortTokenDecimals = IERC20Metadata(_shortToken).decimals();
        uint256 baseTokenDecimals = IERC20Metadata(_baseToken).decimals();
        uint256 baseTokenConversion = 10 ** (18 - baseTokenDecimals);

        uint256 priceOfShortTokenInBase = _shortToken.pricedIn(_baseToken) / baseTokenConversion; // Units: base token decimals
        uint256 amountShortTokenBase =
            (_shortTokenAmount * priceOfShortTokenInBase).dividedBy(10 ** shortTokenDecimals, 0); // Units: base token decimals

        uint256 shaaveLTV = getShaaveLTV(_baseToken);

        return (amountShortTokenBase / shaaveLTV) * 100;
    }

    function getShaaveLTV(address _baseToken) internal view returns (uint256) {
        uint256 bitMap = IPool(AAVE_POOL).getReserveData(_baseToken).configuration.data;
        uint256 aaveLTV = (bitMap & ((1 << 16) - 1)) / 100; // bit 0-15: LTV
        return aaveLTV - LTV_BUFFER;
    }
}
