// contracts/libraries/ReturnCapital.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

/**
 * @title Array library
 * @author shAave
 * @dev Implements the logic for manipulating arrays.
*/
library AddressArray {

    function removeAddress(address[] storage _array, address _address) internal {
        for (uint i; i<_array.length; i++) {
            if (_array[i] == _address) {
                _array[i] = _array[_array.length - 1];
                _array.pop();
                break;
            }
        }
    }

    function includes(address[] memory _array, address _address) internal pure returns (bool) {
        for (uint i; i<_array.length; i++) {
            if (_array[i] == _address) {
                return true;
            }
        }
        return false;
    }
    
}