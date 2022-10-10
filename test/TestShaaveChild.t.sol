// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../src/contracts/ShaaveChild.sol";
import "./Mocks/MockAavePool.t.sol";
import "./Mocks/MockShaaveChild.t.sol";

contract Test_ShaaveChild is Test {
    using ShaavePricing for address;
    ShaaveChild  shaaveChild;
    address      swapRouterAddress           = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter  public immutable swapRouter = ISwapRouter(swapRouterAddress);                           // Goerli Uniswap SwapRouter Address
    address      baseTokenAddress            = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;               // Goerli Aave USDC
    address      testAaveOracleAddress       = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;               // Goerli Aave Pricing Oracle Address
    address      aavePoolAddress             = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;               // Goerli Aave Pool Address
    address      _userAddress                = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;               // https://vanity-eth.tk/ random-generated

    function setUp() public {
        shaaveChild     = new ShaaveChild(_userAddress);
    }
    
    function test_short_newAddress_noDebt_noShortPositionInluded() public {

        // Arrange
        address _shortTokenAddress         = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464;   // Goerli Aaave DAI
        uint    _collateralTokenAmount     = 10e18;
        uint    inputTokenPriceUSD         = 10e8;                                         // input token in base currency
        uint    baseTokenPriceUSD          = 1e8;                                          // base token in base currency
        bool    success                    = false;
        uint    amountIn                   = 1;
        uint    amountOut                  = 1;
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, _shortTokenAddress),
            abi.encode(inputTokenPriceUSD)
        );
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, baseTokenAddress),
            abi.encode(baseTokenPriceUSD)
        );
        vm.mockCall(
            aavePoolAddress,
            abi.encodeWithSelector(IPool(aavePoolAddress).borrow.selector),
            abi.encode(true)
        );
        vm.mockCall(
            swapRouterAddress,
            abi.encodeWithSelector(ISwapRouter(swapRouterAddress).exactInputSingle.selector),
            abi.encode(amountIn, amountOut)
        );

        // Act
        success = shaaveChild.short(_shortTokenAddress, _collateralTokenAmount, _userAddress);

        // Assert
        assertEq(success, true);
    }
}