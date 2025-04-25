//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title  WarpColors
 * @author Hurls
 * @notice The seven colors of Warps.
 */
library WarpColors {
    /// @dev These are sorted in a gradient.
    function colors() public pure returns (string[7] memory) {
        return [
            "FF007A", // Uniswap Pink
            "855DCD", // Farcaster Purple
            "FF9900", // Bitcoin Orange
            "FFCC00", // IKEA Yellow
            "2BDE73", // Kickstarter Green
            "00FFFF", // Cyan
            "FFFFFF" // White
        ];
    }

    /**
     * @notice Get the color string at a specific index.
     * @param _index The index (0-6) of the color to retrieve.
     * @return The hex string of the color at the specified index.
     * @dev Reverts if the index is out of bounds.
     */
    function getColorByIndex(uint8 _index) public pure returns (string memory) {
        require(_index < 7, "Index out of bounds");
        return colors()[_index];
    }

    /**
     * @notice Get the index of a specific color string.
     * @param _color The hex string of the color to find.
     * @return The index (0-6) of the color.
     * @dev Reverts if the color is not found in the list.
     */
    function getIndexByColor(string memory _color) public pure returns (uint8) {
        string[7] memory _colors = colors();
        bytes32 colorHash = keccak256(abi.encodePacked(_color));

        for (uint8 i = 0; i < 7; i++) {
            if (keccak256(abi.encodePacked(_colors[i])) == colorHash) {
                return i;
            }
        }
        revert("Color not found");
    }
}
