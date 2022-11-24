// contracts/ShaaveParent.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// External Packages
import "@aave-protocol/interfaces/IPool.sol";
import "@aave-protocol/interfaces/IAaveOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

// Local
import "../interfaces/IShaaveChild.sol";
import "./ShaaveChild.sol";
import "./libraries/ShaavePricing.sol";
import "../interfaces/IwERC20.sol";


/// @title shAave parent contract, which orchestrates children contracts
contract ShaaveParent is Ownable {
    using ShaavePricing for address;
    using AddressArray for address[];
    using Math for uint;

    // -- ShaaveParent Variables --
    mapping(address => mapping(address => address)) public userContracts;
    address[] private childContracts;
    uint public ltvBuffer;

    // -- Aave Variables --
    address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
      
    // -- Events --
    event CollateralSuccess(address user, address baseTokenAddress, uint amount);
    
    constructor(uint _ltvBuffer) {
        ltvBuffer = _ltvBuffer;
    }

    /** 
    * @dev This pass-through function is used to add to a user's short position.
    * @param _shortToken The address of the short token the user wants to reduce his or her position in.
    * @param _baseToken The address of the token that's used for collateral.
    * @param _baseTokenAmount The amount of collateral that will be used for adding to a short position.
    **/
    function addShortPosition(
        address _shortToken,
        address _baseToken,
        uint _baseTokenAmount
    ) public returns (bool) {
        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        require(reserves.includes(_baseToken), "Base token not supported.");

        // 1. Create new user's child contract, if the user does not already have one
        address child = userContracts[msg.sender][_baseToken];

        if (child == address(0)) {
            uint shaaveLTV = getShaaveLTV(_baseToken);
            uint decimals = IwERC20(_shortToken).decimals();
            child = address(new ShaaveChild(msg.sender, _baseToken, decimals, shaaveLTV));
            userContracts[msg.sender][_baseToken] = child;
            childContracts.push(child);
        }

        // 2. Supply collateral on behalf of user's child contract        
        supplyOnBehalfOfChild(child, _baseToken, _baseTokenAmount);

        // 3. Finish shorting process on user's child contract
        IShaaveChild(child).short(_shortToken, _baseTokenAmount, msg.sender);
        return true;
    }

    /** 
    * @dev Used to supply collateral on a user's child contract's behalf.
    * @param _userChildContract The address of the user's child contract's behalf.
    * @param _baseToken The address of the token that's used for collateral.
    * @param _baseTokenAmount The amount of collateral that will be used for adding to a short position.
    **/
    function supplyOnBehalfOfChild(address _userChildContract, address _baseToken, uint _baseTokenAmount) private returns (bool) {
        // 1. Transfer the user's collateral amount to this contract, so it can supply collateral to Aave
        IERC20(_baseToken).transferFrom(msg.sender, address(this), _baseTokenAmount);
        // 2. Approve Aave to handle collateral on this contract's behalf
        IERC20(_baseToken).approve(AAVE_POOL, _baseTokenAmount);

        // 3. Supply collateral to Aave, on the user's child contract's behalf
        IPool(AAVE_POOL).supply(_baseToken, _baseTokenAmount, _userChildContract, 0);

        emit CollateralSuccess(msg.sender, _baseToken, _baseTokenAmount);

        return true;
    }

    /** 
    * @dev Returns the amount of a collateral necessary for a desired amount of a short position.
    * @param _shortToken The address of the token the user wants to short.
    * @param _baseToken The address of the token that's used for collateral.
    * @param _shortTokenAmount The amount of the token the user wants to short (in WEI).
    * @return amount The amount of the collateral token the user will need to supply, in order to short the inputted amount of the short token.
    **/
    function getNeededCollateralAmount(
        address _shortToken,
        address _baseToken,
        uint _shortTokenAmount
    ) public view returns (uint) {
        uint shaaveLTV = getShaaveLTV(_baseToken);
        uint priceOfShortTokenInBase = _shortToken.pricedIn(_baseToken);                                    // Wei
        uint amountShortTokenBase = (_shortTokenAmount * priceOfShortTokenInBase).dividedBy(1e18, 0);       // Wei

        return (amountShortTokenBase.dividedBy(shaaveLTV, 0)) * 100;
    }
    
    /** 
    * @dev Returns the Shaave-imposed LTV for a given collateral asset.
    * @param _baseToken The address of the base token.
    * @return shaaveLTV The Shaave-imposed loan to value ratio.
    **/
    function getShaaveLTV(address _baseToken) private view returns (uint) {
        uint bitMap = IPool(AAVE_POOL).getReserveData(_baseToken).configuration.data;
        uint aaveLTV = (bitMap & ((1 << 16) - 1)) / 100;  // bit 0-15: LTV
        return aaveLTV - ltvBuffer;
    }

    /*******************************************************************************
    **
    **  Admin functions
    **
    *******************************************************************************/

    /** 
    * @dev Returns a an array of all users' associated child contracts.
    * @return children An array of all users' associated child contracts.
    **/
    function retrieveChildContracts() external view onlyOwner returns (address[] memory) {
        return childContracts;
    }

    /** 
    * @dev Returns a an array of a single user's associated child contracts.
    * @return children An array of a single user's associated child contracts.
    **/
    function retreiveChildrenByUser() external view onlyOwner returns (address[] memory) {
        address[] memory children;
        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        for (uint i; i < reserves.length; i++) {
            address child = userContracts[msg.sender][reserves[i]];
            if (child != address(0)) {
                children[i] = child;
            }
        }
        return children;
    }
}