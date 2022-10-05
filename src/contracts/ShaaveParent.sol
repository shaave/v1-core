// contracts/ShaaveParent.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

// External Packages
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@aave-protocol/interfaces/IPool.sol";
import "@aave-protocol/interfaces/IAaveOracle.sol";

// Local
import "../interfaces/IShaaveChild.sol";
import "./ShaaveChild.sol";
import "./libraries/ShaavePricing.sol";


/// @title shAave parent contract, which orchestrates children contracts
contract ShaaveParent {

    // -- ShaaveParent Variables --
    address private admin;
    mapping(address => address) private userContracts;
    address[] private childContracts;

    // -- Aave Variables --
    address public baseTokenAddress = 0xA2025B15a1757311bfD68cb14eaeFCc237AF5b43;    // Goerli Aave USDC
    address public aavePoolAddress = 0x368EedF3f56ad10b9bC57eed4Dac65B26Bb667f6;           // Goerli Aave Pool Address
    address public aaveOracleAddress = 0x5bed0810073cc9f0DacF73C648202249E87eF6cB;         // Goerli Aave Oracle Address
    
    // -- Events --
    event CollateralSuccess(address user, address shortTokenAddress, uint amount);
    
    constructor() {
        admin = payable(msg.sender);
    }

    /** 
    * @dev This pass-through function is used to add to a user's short position.
    * @param _shortTokenAddress The address of the short token the user wants to reduce his or her position in.
    * @param _collateralTokenAmount The amount of collateral that will be used for adding to a short position.
    **/
    function addShortPosition(
        address _shortTokenAddress,
        uint _collateralTokenAmount
    ) public returns (bool success) {
        require(_collateralTokenAmount > 0, "_collateralTokenAmount must be a positive value.");
        require(_shortTokenAddress != address(0), "_shortTokenAddress must be a nonzero address.");

        // 1. Create new user's child contract, if the user does not already have one
        address userChildContract = userContracts[msg.sender];

        if (userChildContract == address(0)) {
            ShaaveChild userChildContract = new ShaaveChild();
            userContracts[msg.sender] = address(userChildContract);
            childContracts.push(address(userChildContract));
        }

        // 2. Supply collateral on behalf of user's child contract        
        supplyOnBehalfOfChild(userChildContract, _collateralTokenAmount);

        // 3. Finish shorting process by calling finishShortingProcess() on user's child contract
        IShaaveChild(userChildContract).short(_shortTokenAddress, _collateralTokenAmount, msg.sender);
    }


    /** 
    * @dev This private function (only accessible by this contract) is used to supply collateral on a user's child contract's behalf.
    * @param _userChildContract The address of the user's child contract's behalf.
    * @param _collateralTokenAmount The amount of collateral that will be used for adding to a short position.
    **/
    function supplyOnBehalfOfChild(address _userChildContract, uint _collateralTokenAmount) private returns (bool) {
        // 1. Transfer the user's collateral amount to this contract, so it can supply collateral to Aave
        IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), _collateralTokenAmount);

        // 2. Approve Aave to handle collateral on this contract's behalf
        IERC20(collateralTokenAddress).approve(aavePoolAddress, _collateralTokenAmount);

        // 3. Supply collateral to Aave, on the user's child contract's behalf
        IPool(aavePoolAddress).supply(collateralTokenAddress, _collateralTokenAmount, _userChildContract, 0);
        emit CollateralSuccess(msg.sender, _collateralTokenAmount);
    }

    /** 
    * @dev This function returns the amount of a collateral necessary for a desired amount of a short position.
    * @param _collateralTokenAddress The address of the token the user wants to post as collateral.
    * @param _shortTokenAddress The address of the token the user wants to short.
    * @param _shortTokenAmount The amount of the token the user wants to short (in WEI).
    * @return collateralTokenAmount The amount of the collateral token the user will need to supply, in order to short the inputted amount of the short token.
    **/
    function getNeededCollateralAmount(
        address _collateralTokenAddress,
        address _shortTokenAddress,
        uint _shortTokenAmount
    ) public pure returns (uint collateralTokenAmount) {
        uint priceOfShortTokenInBase = ShaavePricing.getAssetPriceInBase(baseTokenAddress, _shortTokenAddress);  
        uint amountShortTokenBase = (_shortTokenAmount * priceOfShortTokenInBase) / 1e18;                   // TODO: fix
        collateralTokenAmount = (amountShortTokenBase / .70);                                               // TODO: Ain't gonna work
    }

    /** 
    * @dev This function returns a calling user's delegated contract address, if they have one.
    * @return userChildContract The user's delegated contract address.
    **/
    function returnChildContractBySender() public returns (address userChildContract) {
        userChildContract = userContracts[msg.sender];
        require(userChildContract != address(0), "User doesn't have a shAave account.");
    }

    /** 
    * @dev This adminOnly function returns a user's delegated contract address, if they have one.
    * @param _userAddress a shAave user's address
    * @return userChildContract The user's delegated contract address.
    **/
    function returnUserContractByAddress(address _userAddress) public adminOnly returns (address userChildContract) {
        userChildContract = userContracts[_userAddress];
        require(userChildContract != address(0), "User doesn't have a shAave account.");
    }

    /** 
    * @dev This adminOnly function returns a an array of all users' associated child contracts.
    * @return userChildContract The user's delegated contract address.
    **/
    function retrieveChildContracts() public adminOnly returns (address[]) {
        return childContracts;
    }

    modifier adminOnly() {
        require(msg.sender == admin);
        _;
    }

}