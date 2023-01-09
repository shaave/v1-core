// contracts/libraries/CapitalLib.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title Array library
 * @author shAave
 * @dev Implements the logic for manipulating arrays.
 */
library AddressLib {
    function removeAddress(address[] storage _array, address _address) internal {
        for (uint256 i; i < _array.length; i++) {
            if (_array[i] == _address) {
                _array[i] = _array[_array.length - 1];
                _array.pop();
                break;
            }
        }
    }

    function includes(address[] memory _array, address _address) internal pure returns (bool) {
        for (uint256 i; i < _array.length; i++) {
            if (_array[i] == _address) {
                return true;
            }
        }
        return false;
    }
}
