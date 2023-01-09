// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// External Packages
import "@aave-protocol/interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "solmate/utils/SafeTransferLib.sol";

// Local
import "../child/Child.sol";
import "../libraries/PricingLib.sol";
import "../interfaces/IChild.sol";
import "../interfaces/IERC20Metadata.sol";

/// @title shAave parent contract, which orchestrates children contracts
contract Parent is Ownable {
    using PricingLib for address;
    using AddressLib for address[];
    using MathLib for uint256;

    // -- Parent Variables --
    mapping(address => mapping(address => address)) public userContracts;
    address[] private childContracts;
    uint256 public ltvBuffer;

    // -- Aave Variables --
    address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public constant AAVE_DATA_PROVIDER = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;

    // -- Events --
    event CollateralSuccess(address user, address baseTokenAddress, uint256 amount);

    constructor(uint256 _ltvBuffer) {
        ltvBuffer = _ltvBuffer;
    }

    /**
     * @dev This pass-through function is used to add to a user's short position.
     * @param _shortToken The address of the short token the user wants to reduce his or her position in.
     * @param _baseToken The address of the token that's used for collateral.
     * @param _baseTokenAmount The amount of collateral that will be used for adding to a short position.
     *
     */
    function addShortPosition(address _shortToken, address _baseToken, uint256 _baseTokenAmount)
        public
        returns (bool)
    {
        // 1. Create new user's child contract, if the user does not already have one
        address child = userContracts[msg.sender][_baseToken];

        if (child == address(0)) {
            uint256 shaaveLTV = getShaaveLTV(_baseToken);
            uint256 decimals = IERC20Metadata(_baseToken).decimals();
            child = address(new Child(msg.sender, _baseToken, decimals, shaaveLTV));
            userContracts[msg.sender][_baseToken] = child;
            childContracts.push(child);
        }

        // 2. Foward base token to child
        SafeTransferLib.safeTransferFrom(ERC20(_baseToken), msg.sender, child, _baseTokenAmount);

        // 3. Finish shorting process on user's child contract
        IChild(child).short(_shortToken, _baseTokenAmount, msg.sender);
        return true;
    }

    /**
     * @dev Returns the amount of a collateral necessary for a desired amount of a short position.
     * @param _shortToken The address of the token the user wants to short.
     * @param _baseToken The address of the token that's used for collateral.
     * @param _shortTokenAmount The amount of the token the user wants to short (Units: short token decimals).
     * @return amount Amount of collateral necessary for desired short position (Units: base token decimals).
     *
     */
    function getNeededCollateralAmount(address _shortToken, address _baseToken, uint256 _shortTokenAmount)
        public
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

    /**
     * @dev Returns the Shaave-imposed LTV for a given collateral asset.
     * @param _baseToken The address of the base token.
     * @return shaaveLTV The Shaave-imposed loan to value ratio.
     *
     */
    function getShaaveLTV(address _baseToken) private view returns (uint256) {
        uint256 bitMap = IPool(AAVE_POOL).getReserveData(_baseToken).configuration.data;
        uint256 aaveLTV = (bitMap & ((1 << 16) - 1)) / 100; // bit 0-15: LTV
        return aaveLTV - ltvBuffer;
    }

    /**
     *
     *
     * Admin functions
     *
     *
     */

    /**
     * @dev Returns a an array of all users' associated child contracts.
     * @return children An array of all users' associated child contracts.
     *
     */
    function retrieveChildContracts() external view onlyOwner returns (address[] memory) {
        return childContracts;
    }

    /**
     * @dev Returns a an array of a single user's associated child contracts.
     * @return children An array of a single user's associated child contracts.
     *
     */
    function retreiveChildrenByUser() external view onlyOwner returns (address[2][] memory) {
        address[] memory reserves = IPool(AAVE_POOL).getReservesList();

        address[2][] memory childDataArray = new address[2][](reserves.length);
        for (uint256 i; i < reserves.length; i++) {
            address child = userContracts[msg.sender][reserves[i]];
            if (child != address(0)) {
                childDataArray[i] = [child, reserves[i]];
            }
        }

        return childDataArray;
    }
}
