// contracts/ShaaveParent.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// External Packages
import "@aave-protocol/interfaces/IPool.sol";
import "@aave-protocol/interfaces/IAaveOracle.sol";
import "forge-std/console.sol";

// Local
import "../interfaces/IShaaveChild.sol";
import "./ShaaveChild.sol";
import "./libraries/ShaavePricing.sol";


/// @title shAave parent contract, which orchestrates children contracts
contract ShaaveParent {
    using ShaavePricing for address;
    using Math for uint;

    // -- ShaaveParent Variables --
    address private admin;
    mapping(address => address) public userContracts;
    address[] private childContracts;
    uint ltvBuffer;

    // -- Aave Variables --
    address public aavePoolAddress;
    address public aaveOracleAddress;        
    
    // -- Events --
    event CollateralSuccess(address user, address baseTokenAddress, uint amount);
    
    constructor(address _aavePoolAddress, address _aaveOracleAddress, uint _ltvBuffer) {
        admin = payable(msg.sender);
        aavePoolAddress = _aavePoolAddress;
        aaveOracleAddress = _aaveOracleAddress;
        ltvBuffer = _ltvBuffer;
    }

    /** 
    * @dev This pass-through function is used to add to a user's short position.
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _baseTokenAddress The address of the token that's used for collateral.
    * @param _baseTokenAmount The amount of collateral that will be used for adding to a short position.
    **/
    function addShortPosition(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _baseTokenAmount
    ) public returns (bool) {

        // 1. Create new user's child contract, if the user does not already have one
        address childContractAddress = userContracts[msg.sender];

        if (childContractAddress == address(0)) {
            childContractAddress = address(new ShaaveChild(msg.sender, aavePoolAddress, aaveOracleAddress));
            userContracts[msg.sender] = childContractAddress;
            childContracts.push(childContractAddress);
        }

        // 2. Supply collateral on behalf of user's child contract        
        supplyOnBehalfOfChild(childContractAddress, _baseTokenAddress, _baseTokenAmount);

        // 3. Finish shorting process on user's child contract
        uint shaaveLTV = getShaaveLTV(_shortTokenAddress);
        IShaaveChild(childContractAddress).short(_shortTokenAddress, _baseTokenAddress, _baseTokenAmount, shaaveLTV, msg.sender);
        return true;
    }

    /** 
    * @dev This private function (only accessible by this contract) is used to supply collateral on a user's child contract's behalf.
    * @param _userChildContract The address of the user's child contract's behalf.
    * @param _baseTokenAddress The address of the token that's used for collateral.
    * @param _baseTokenAmount The amount of collateral that will be used for adding to a short position.
    **/
    function supplyOnBehalfOfChild(address _userChildContract, address _baseTokenAddress, uint _baseTokenAmount) private returns (bool) {
        // 1. Transfer the user's collateral amount to this contract, so it can supply collateral to Aave
        IERC20(_baseTokenAddress).transferFrom(msg.sender, address(this), _baseTokenAmount);
        // 2. Approve Aave to handle collateral on this contract's behalf
        IERC20(_baseTokenAddress).approve(aavePoolAddress, _baseTokenAmount);

        // 3. Supply collateral to Aave, on the user's child contract's behalf
        IPool(aavePoolAddress).supply(_baseTokenAddress, _baseTokenAmount, _userChildContract, 0);

        emit CollateralSuccess(msg.sender, _baseTokenAddress, _baseTokenAmount);

        return true;
    }

    /** 
    * @dev This function returns the amount of a collateral necessary for a desired amount of a short position.
    * @param _shortTokenAddress The address of the token the user wants to short.
    * @param _baseTokenAddress The address of the token that's used for collateral.
    * @param _shortTokenAmount The amount of the token the user wants to short (in WEI).
    * @return collateralTokenAmount The amount of the collateral token the user will need to supply, in order to short the inputted amount of the short token.
    **/
    function getNeededCollateralAmount(
        address _shortTokenAddress,
        address _baseTokenAddress,
        uint _shortTokenAmount
    ) public view returns (uint) {
        uint shaaveLTV = getShaaveLTV(_shortTokenAddress);
        uint priceOfShortTokenInBase = _shortTokenAddress.pricedIn(_baseTokenAddress);                      // Wei
        uint amountShortTokenBase = (_shortTokenAmount * priceOfShortTokenInBase).dividedBy(1e18, 0);       // Wei
        uint collateralTokenAmount = (amountShortTokenBase.dividedBy(shaaveLTV, 0)) * 100;                  // Wei

        return collateralTokenAmount;
    }

    function getShaaveLTV(address _shortTokenAddress) private view returns (uint) {
        uint bitMap = IPool(aavePoolAddress).getReserveData(_shortTokenAddress).configuration.data;
        uint lastNbits = 16;               // bit 0-15: LTV
        uint mask = (1 << lastNbits) - 1;
        uint aaveLTV = (bitMap & mask) / 100;
        return aaveLTV - ltvBuffer;
    }

    /** 
    * @dev This adminOnly function returns a an array of all users' associated child contracts.
    * @return userChildContract The user's delegated contract address.
    **/
    function retrieveChildContracts() external view adminOnly returns (address[] memory) {
        return childContracts;
    }

    modifier adminOnly() {
        require(msg.sender == admin);
        _;
    }
}