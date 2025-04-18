//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Utilities {
    /// @dev Zero-index based pseudorandom number based on one input and max bound
    function random(uint256 input, uint256 _max) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(input))) % _max);
    }

    /// @dev Zero-index based salted pseudorandom number based on two inputs and max bound
    function random(uint256 input, string memory salt, uint256 _max) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(input, salt))) % _max);
    }

    /// @dev Convert an integer to a string
    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            ++len;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    /// @dev Get the smallest non zero number
    function minGt0(uint8 one, uint8 two) internal pure returns (uint8) {
        return one > two ? two > 0 ? two : one : one;
    }

    /// @dev Get the smaller number
    function min(uint8 one, uint8 two) internal pure returns (uint8) {
        return one < two ? one : two;
    }

    /// @dev Get the larger number
    function max(uint8 one, uint8 two) internal pure returns (uint8) {
        return one > two ? one : two;
    }

    /// @dev Get the average between two numbers
    function avg(uint8 one, uint8 two) internal pure returns (uint8 result) {
        unchecked {
            result = (one >> 1) + (two >> 1) + (one & two & 1);
        }
    }

    /// @dev Get the days since another date (input is seconds)
    function day(uint256 from, uint256 to) internal pure returns (uint24) {
        return uint24((to - from) / 24 hours + 1);
    }
}
