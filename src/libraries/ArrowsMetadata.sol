//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "lib/openzeppelin-contracts/contracts/utils/Base64.sol";

import "./ArrowsArt.sol";
import "../interfaces/IArrows.sol";
import "./Utilities.sol";

/**
 * @title  ArrowsMetadata
 * @author Hurls
 * @notice Renders ERC721 compatible metadata for Arrows.
 */
library ArrowsMetadata {
    /// @dev Render the JSON Metadata for a given Arrows token.
    /// @param tokenId The id of the token to render.
    /// @param arrows The DB containing all arrows.
    function tokenURI(uint256 tokenId, IArrows.Arrows storage arrows) public view returns (string memory) {
        IArrows.Arrow memory arrow = ArrowsArt.getArrow(tokenId, arrows);

        // Generate both static and animated versions
        bytes memory staticSvg = ArrowsArt.generateSVG(arrow, arrows);

        bytes memory metadata = abi.encodePacked(
            "{",
            '"name": "Dollars ',
            Utilities.uint2str(tokenId),
            '",',
            '"description": "Up and to the right.",',
            '"image": ',
            '"data:image/svg+xml;base64,',
            Base64.encode(staticSvg),
            '",',
            '"attributes": [',
            attributes(arrow),
            "]",
            "}"
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(metadata)));
    }

    /// @dev Render the JSON atributes for a given Arrows token.
    /// @param arrow The arrow to render.
    function attributes(IArrows.Arrow memory arrow) public pure returns (bytes memory) {
        bool showVisualAttributes = arrow.hasManyArrows;

        return abi.encodePacked(
            showVisualAttributes
                ? trait("Color Band", colorBand(ArrowsArt.colorBandIndex(arrow, arrow.stored.divisorIndex)), ",")
                : "",
            showVisualAttributes
                ? trait("Gradient", gradients(ArrowsArt.gradientIndex(arrow, arrow.stored.divisorIndex)), ",")
                : "",
            trait("Arrows", Utilities.uint2str(arrow.arrowsCount), "")
        );
    }

    /// @dev Get the names for different gradients. Compare ArrowsArt.GRADIENTS.
    /// @param gradientIndex The index of the gradient.
    function gradients(uint8 gradientIndex) public pure returns (string memory) {
        return ["None", "Linear", "Double Linear", "Reflected", "Double Angled", "Angled", "Linear Z"][gradientIndex];
    }

    /// @dev Get the percentage values for different color bands. Compare ArrowsArt.COLOR_BANDS.
    /// @param bandIndex The index of the color band.
    function colorBand(uint8 bandIndex) public pure returns (string memory) {
        return ["Eighty", "Sixty", "Forty", "Twenty", "Ten", "Five", "One"][bandIndex];
    }

    /// @dev Generate the SVG snipped for a single attribute.
    /// @param traitType The `trait_type` for this trait.
    /// @param traitValue The `value` for this trait.
    /// @param append Helper to append a comma.
    function trait(string memory traitType, string memory traitValue, string memory append)
        public
        pure
        returns (string memory)
    {
        return
            string(abi.encodePacked("{", '"trait_type": "', traitType, '",' '"value": "', traitValue, '"' "}", append));
    }

    /// @dev Generate the HTML for the animation_url in the metadata.
    /// @param tokenId The id of the token to generate the embed for.
    /// @param svg The rendered SVG code to embed in the HTML.
    function generateHTML(uint256 tokenId, bytes memory svg) public pure returns (bytes memory) {
        return abi.encodePacked(
            "<!DOCTYPE html>",
            '<html lang="en">',
            "<head>",
            '<meta charset="UTF-8">',
            '<meta http-equiv="X-UA-Compatible" content="IE=edge">',
            '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
            "<title>Arrow #",
            Utilities.uint2str(tokenId),
            "</title>",
            "<style>",
            "html,",
            "body {",
            "margin: 0;",
            "background: #EFEFEF;",
            "overflow: hidden;",
            "}",
            "svg {",
            "max-width: 100vw;",
            "max-height: 100vh;",
            "}",
            "</style>",
            "</head>",
            "<body>",
            svg,
            "</body>",
            "</html>"
        );
    }
}
