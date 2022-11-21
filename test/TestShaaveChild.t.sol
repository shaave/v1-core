// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../src/contracts/ShaaveChild.sol";
import "forge-std/console.sol";

contract Test_ShaaveChild is Test {
    using ShaavePricing for address;
    using Math for uint;
    ShaaveChild  testShaaveChild;                                                                        // test contract instance of ShaaveChild (bare)
    ShaaveChild  testShaaveChildOpenShorts;                                                              // test contract instance of ShaaveChild (with shorts)
    address      swapRouterAddress           = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter  public immutable swapRouter = ISwapRouter(swapRouterAddress);                           // Goerli Uniswap SwapRouter Address
    address      baseTokenAddress            = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;               // Goerli Aave USDC
    address      shortTokenAddressDAI        = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464;               // Goerli Aave DAI
    address      shortTokenAddressWETH       = 0x2e3A2fb8473316A02b8A297B982498E661E1f6f5;               // Goerli Aave WETH   
    address      shortTokenAddressWBTC       = 0x8869DFd060c682675c2A8aE5B21F2cF738A0E3CE;               // Goerli Aave WBTC
    address      testAaveOracleAddress       = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;               // Goerli Aave Pricing Oracle Address
    address      testAavePoolAddress         = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;               // Goerli Aave Pool Address
    address      _userAddress                = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;               // https://vanity-eth.tk/ random-generated
    address      _userAddressWithOpenShorts  = 0x476c02dfe2166fB8489Ed52836F4c5DEc8d066CE;               // https://vanity-eth.tk/ random-generated
    address[]    shortAddresses              = [shortTokenAddressDAI, 
                                                shortTokenAddressWETH, 
                                                shortTokenAddressWBTC];
    uint[]       dummyInputTokenPricesUSD    = [10e8, 5e8, 7e8];                                         // input tokens in base currency
    uint[]       dummyBaseTokenPriceUSD      = [1e8, 1e8, 1e8];                                          // base token in base currency
    uint[]       dummyAmountsOut             = [2e18, 5e18, 3e18];
    uint         dummyAmountIn               = 1;
    uint         _collateralTokenAmount      = 10e18;
    uint         shaaveLoanToValueRatio      = 70;

    function setUp() public {
        testShaaveChild           = new ShaaveChild(_userAddress, testAavePoolAddress, testAaveOracleAddress);
        testShaaveChildOpenShorts = new ShaaveChild(_userAddressWithOpenShorts, testAavePoolAddress, testAaveOracleAddress);
        
        for (uint i = 0; i < shortAddresses.length; i++){
            vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, shortAddresses[i]),
            abi.encode(dummyInputTokenPricesUSD[i])
            );
            vm.mockCall(
                testAaveOracleAddress,
                abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, baseTokenAddress),
                abi.encode(dummyBaseTokenPriceUSD[i])
            );
            vm.mockCall(
                testAavePoolAddress,
                abi.encodeWithSelector(IPool(testAavePoolAddress).borrow.selector),
                abi.encode(true)
            );
            vm.mockCall(
                swapRouterAddress,
                abi.encodeWithSelector(ISwapRouter(swapRouterAddress).exactInputSingle.selector),
                abi.encode(dummyAmountsOut[i])
            );
            testShaaveChildOpenShorts.short(shortAddresses[i], baseTokenAddress, _collateralTokenAmount, shaaveLoanToValueRatio, _userAddress);
        }
    }
    
    /*******************************************************************************
    **
    **  short tests
    **
    *******************************************************************************/

    function test_short_newAddress_noDebt_noShortPositionInluded() public {

        // Arrange
        uint    inputTokenPriceUSD         = 10e8;                                         // input token in base currency
        uint    baseTokenPriceUSD          = 1e8;                                          // base token in base currency
        bool    success                    = false;
        uint    amountOut                  = 5e18;
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, shortTokenAddressDAI),
            abi.encode(inputTokenPriceUSD)
        );
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, baseTokenAddress),
            abi.encode(baseTokenPriceUSD)
        );
        vm.mockCall(
            testAavePoolAddress,
            abi.encodeWithSelector(IPool(testAavePoolAddress).borrow.selector),
            abi.encode(true)
        );
        vm.mockCall(
            swapRouterAddress,
            abi.encodeWithSelector(ISwapRouter(swapRouterAddress).exactInputSingle.selector),
            abi.encode(amountOut)
        );

        // Act
        success = testShaaveChild.short(shortTokenAddressDAI, baseTokenAddress, _collateralTokenAmount, shaaveLoanToValueRatio, _userAddress);

        // Assert
        assertEq(success, true);
    }

    /*******************************************************************************
    **
    **  getAccountingData tests
    **
    *******************************************************************************/

    function test_getAccountingData() public {

        // Arrange
        bool[3]    memory actualUserHasDebt = [false, false, false];
        address[3] memory actualShortTokenAddress;
        uint[3]    memory actualBaseAmountsRecieved;
        uint[3]    memory actualCollateralAmounts;
        uint[3]    memory actualBackingBaseAmount;
        uint[3]    memory actualShortTokenAmountsSwapped;
        uint[3]    memory expectedShortTokenAmountsSwapped;


        // Act
        for (uint i = 0; i < shortAddresses.length; i++){
            // Actual
            vm.prank(_userAddressWithOpenShorts);
            actualShortTokenAddress[i]        = testShaaveChildOpenShorts.getAccountingData()[i].shortTokenAddress;
            vm.prank(_userAddressWithOpenShorts);
            actualCollateralAmounts[i]        = testShaaveChildOpenShorts.getAccountingData()[i].collateralAmounts[0];
            vm.prank(_userAddressWithOpenShorts);
            actualShortTokenAmountsSwapped[i] = testShaaveChildOpenShorts.getAccountingData()[i].shortTokenAmountsSwapped[0];
            vm.prank(_userAddressWithOpenShorts);
            actualBaseAmountsRecieved[i]      = testShaaveChildOpenShorts.getAccountingData()[i].baseAmountsReceived[0];
            vm.prank(_userAddressWithOpenShorts);
            actualBackingBaseAmount[i]        = testShaaveChildOpenShorts.getAccountingData()[i].backingBaseAmount;

            // Expected
            expectedShortTokenAmountsSwapped[i] = ((_collateralTokenAmount * shaaveLoanToValueRatio).dividedBy(100, 0)).dividedBy(dummyInputTokenPricesUSD[i].dividedBy(dummyBaseTokenPriceUSD[i], 18), 18);   
        }
        
        // Assert
        for (uint i; i < shortAddresses.length; i++) {
            assertEq(actualUserHasDebt[i], true);
            assertEq(actualShortTokenAddress[i], shortAddresses[i]);
            assertEq(actualCollateralAmounts[i], _collateralTokenAmount);
            assertEq(actualShortTokenAmountsSwapped[i], expectedShortTokenAmountsSwapped[i]);
            assertEq(actualBaseAmountsRecieved[i], dummyAmountsOut[i]);
            assertEq(actualBackingBaseAmount[i], dummyAmountsOut[i]);
        }
    }
}