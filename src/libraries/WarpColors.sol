//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title  WarpColors
 * @author Hurls
 * @notice The ten colors of Warps.
 */
library WarpColors {
    /// @dev These are sorted by brand.
    function colors() public pure returns (string[10] memory) {
        return [
            "FF007A", // Uniswap
            "0052FF", // Coinbase
            "855DCD", // Farcaster
            "472A92", // Warpcast
            "FF9900", // Bitcoin
            "ed1c16", // Coca-cola
            "ffc836", // McDonalds
            "52b043", // XBOX
            "00704a", // Starbucks
            "1da1f2" // Twitter
        ];
    }

    /**
     * @notice Get the color string at a specific index.
     * @param _index The index (0-9) of the color to retrieve.
     * @return The hex string of the color at the specified index.
     * @dev Reverts if the index is out of bounds.
     */
    function getColorByIndex(uint8 _index) public pure returns (string memory) {
        require(_index < 10, "Index out of bounds");
        return colors()[_index];
    }

    /**
     * @notice Get the index of a specific color string.
     * @param _color The hex string of the color to find.
     * @return The index (0-9) of the color.
     * @dev Reverts if the color is not found in the list.
     */
    function getIndexByColor(string memory _color) public pure returns (uint8) {
        string[10] memory _colors = colors();
        bytes32 colorHash = keccak256(abi.encodePacked(_color));

        for (uint8 i = 0; i < 10; i++) {
            if (keccak256(abi.encodePacked(_colors[i])) == colorHash) {
                return i;
            }
        }
        revert("Color not found");
    }
}
