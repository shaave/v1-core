// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../src/contracts/libraries/ReturnCapital.sol";
import "../../src/contracts/libraries/Math.sol";

contract Test_ReturnCapital is Test {
    using Math for uint;

    function test_calculatePositionGains_noGains() public {

        // Arrange
        address testAaveOracleAddress      = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;   // Goerli Aave Pricing Oracle Address
        address _shortTokenAddress         = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464;   // Goerli Aaave DAI
        address _baseTokenAddress          = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;   // Goerli Aaave USDC
        uint    inputTokenPriceUSD         = 10e8;                                         // input token in base currency
        uint    baseTokenPriceUSD          = 1e8;                                          // base token in base currency
        uint    _percentageReduction       = 100;                                          // Attempt to close out position 
        uint    _positionbackingBaseAmount = 149e18;                                       // The amount of base asset in Wei (debtValueBase = 150e18)
        uint    _totalShortTokenDebt       = 15e18;                                        // The contract's total debt in Wei for a specific short token
        uint    gains;                                                                     // The gains the trade at hand yielded; if nonzero, this value (in Wei) will be paid out to the user.

        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, _shortTokenAddress),
            abi.encode(inputTokenPriceUSD)
        );
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, _baseTokenAddress),
            abi.encode(baseTokenPriceUSD)
        );

        // Act
        gains = ReturnCapital.calculatePositionGains(_shortTokenAddress, _baseTokenAddress, _percentageReduction, _positionbackingBaseAmount, _totalShortTokenDebt);

        // Assert
        assertEq(gains, 0);
    }

    function test_calculatePositionGains_gains() public {

        // Arrange
        address testAaveOracleAddress      = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;   // Goerli Aave Pricing Oracle Address
        address _shortTokenAddress         = 0xDF1742fE5b0bFc12331D8EAec6b478DfDbD31464;   // Goerli Aaave DAI
        address _baseTokenAddress          = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;   // Goerli Aaave USDC
        uint    inputTokenPriceUSD         = 10e8;                                         // input token in base currency
        uint    baseTokenPriceUSD          = 1e8;                                          // base token in base currency
        uint    _percentageReduction       = 100;                                          // Attempt to close out position 
        uint    _positionbackingBaseAmount = 155e18;                                       // The amount of base asset in Wei (debtValueBase = 150e18)
        uint    _totalShortTokenDebt       = 15e18;                                        // The contract's total debt in Wei for a specific short token
        uint    gains;                                                                     // The gains the trade at hand yielded; if nonzero, this value (in Wei) will be paid out to the user.

        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, _shortTokenAddress),
            abi.encode(inputTokenPriceUSD)
        );
        vm.mockCall(
            testAaveOracleAddress,
            abi.encodeWithSelector(IAaveOracle(testAaveOracleAddress).getAssetPrice.selector, _baseTokenAddress),
            abi.encode(baseTokenPriceUSD)
        );

        // Act
        gains = ReturnCapital.calculatePositionGains(_shortTokenAddress, _baseTokenAddress, _percentageReduction, _positionbackingBaseAmount, _totalShortTokenDebt);

        // Assert
        assertEq(gains, 5e18);
    }

    function test_calculateCollateralWithdrawAmount() public {

        // Arrange
        address aavePoolAddress     = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;   // Goerli Aave Pool Address
        address _childAddress       = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;   // https://vanity-eth.tk/ random-generated
        uint    withdrawalAmount;
        uint    totalCollateralBase = 10e8;
        uint    totalDebtBase       = 7e8;

        vm.mockCall(
            aavePoolAddress,
            abi.encodeWithSelector(IPool(aavePoolAddress).getUserAccountData.selector, _childAddress),
            abi.encode(totalCollateralBase, totalDebtBase, 0, 0, 0, 0)
        );

        // Act
        withdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(_childAddress);
        
        // Assert
        assertEq(withdrawalAmount, 0);
    }

    function test_calculateCollateralWithdrawAmount_zeroWithdrawal() public {

        // Arrange
        address aavePoolAddress     = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;   // Goerli Aave Pool Address
        address _childAddress       = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;   // https://vanity-eth.tk/ random-generated
        uint    withdrawalAmount;
        uint    totalCollateralBase = 10e8;
        uint    totalDebtBase       = 7e8;

        vm.mockCall(
            aavePoolAddress,
            abi.encodeWithSelector(IPool(aavePoolAddress).getUserAccountData.selector, _childAddress),
            abi.encode(totalCollateralBase, totalDebtBase, 0, 0, 0, 0)
        );

        // Act
        withdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(_childAddress);
        
        // Assert
        assertEq(withdrawalAmount, 0);
    }

    function test_calculateCollateralWithdrawAmount_zeroWithdrawal_nonZeroWithdrawal() public {

        // Arrange
        address aavePoolAddress        = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;   // Goerli Aave Pool Address
        address _childAddress          = 0xa4F9f089677Bf68c8F38Fe9bffEF2be52EA679bF;   // https://vanity-eth.tk/ random-generated
        uint    totalCollateralBase    = 55e8;
        uint    totalDebtBase          = 7e8;
        uint    ShaaveDebtToCollateral = 70;
        uint    maxUncapturedDebt      = 9999999999;
        uint    uncapturedCollateral   = (maxUncapturedDebt.dividedBy(ShaaveDebtToCollateral,0) * 100);
        uint    expectedWithdrawAmount = ((totalCollateralBase - (totalDebtBase.dividedBy(ShaaveDebtToCollateral, 0) * 100)) * 1e10) - uncapturedCollateral;
        uint    actualwithdrawalAmount;

        vm.mockCall(
            aavePoolAddress,
            abi.encodeWithSelector(IPool(aavePoolAddress).getUserAccountData.selector, _childAddress),
            abi.encode(totalCollateralBase, totalDebtBase, 0, 0, 0, 0)
        );

        // Act
        actualwithdrawalAmount = ReturnCapital.calculateCollateralWithdrawAmount(_childAddress);

        // Assert
        assertEq(actualwithdrawalAmount, expectedWithdrawAmount);
    }
}