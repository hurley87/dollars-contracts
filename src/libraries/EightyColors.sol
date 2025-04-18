//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title  EightyColors
 * @author Hurls
 * @notice The eighty colors of Warps.
 */
library EightyColors {
    /// @dev These are sorted in a gradient.
    function colors() public pure returns (string[80] memory) {
        return [
            // Deep purples to violets
            "2D0157",
            "3A0B75",
            "4C1A9E",
            "5B28BC",
            "6B36DB",
            "7B45F9",
            "8860FF",
            "9575FF",
            "A18CFF",
            // Blues
            "0A4BF1",
            "0E5FFF",
            "1E74FF",
            "2E89FF",
            "3E9EFF",
            "4EB3FF",
            "5EC8FF",
            "6EDDFF",
            // Teals and Cyans
            "00B5B5",
            "00C5C5",
            "00D5D5",
            "00E5E5",
            "00F5F5",
            // Greens
            "018A08",
            "029F0E",
            "03B414",
            "04C91A",
            "05DE20",
            "06F326",
            "25FF45",
            "45FF65",
            "65FF85",
            // Yellow-greens
            "85FF65",
            "A5FF45",
            "C5FF25",
            "E5FF05",
            // Yellows
            "FFE600",
            "FFD800",
            "FFCA00",
            "FFBC00",
            "FFAE00",
            // Orange
            "FFA000",
            "FF9200",
            "FF8400",
            "FF7600",
            "FF6800",
            // Coral and Salmon
            "FF5A4F",
            "FF4C41",
            "FF3E33",
            "FF3025",
            "FF2217",
            // Reds
            "FF1409",
            "F01209",
            "E11009",
            "D20E09",
            "C30C09",
            // Deep reds
            "B40A09",
            "A50809",
            "960609",
            "870409",
            "780209",
            // Burgundy to pink
            "690A1E",
            "7A0F33",
            "8B1448",
            "9C195D",
            "AD1E72",
            "BE2387",
            "CF289C",
            "E02DB1",
            "F132C6",
            // Magentas and purples
            "F23ED1",
            "F34ADC",
            "F456E7",
            "F562F2",
            "E77AFF",
            "D886FF",
            "C992FF",
            "BA9EFF",
            "9B89E7",
            "8C68CF",
            "7D47B7"
        ];
    }

    /**
     * @notice Get the color string at a specific index.
     * @param _index The index (0-79) of the color to retrieve.
     * @return The hex string of the color at the specified index.
     * @dev Reverts if the index is out of bounds.
     */
    function getColorByIndex(uint8 _index) public pure returns (string memory) {
        require(_index < 80, "Index out of bounds");
        return colors()[_index];
    }

    /**
     * @notice Get the index of a specific color string.
     * @param _color The hex string of the color to find.
     * @return The index (0-79) of the color.
     * @dev Reverts if the color is not found in the list.
     */
    function getIndexByColor(string memory _color) public pure returns (uint8) {
        string[80] memory _colors = colors();
        bytes32 colorHash = keccak256(abi.encodePacked(_color));

        for (uint8 i = 0; i < 80; i++) {
            if (keccak256(abi.encodePacked(_colors[i])) == colorHash) {
                return i;
            }
        }
        revert("Color not found");
    }
}
