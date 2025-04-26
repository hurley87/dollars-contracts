//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IWarps.sol";
import "./WarpColors.sol";
import "./Utilities.sol";

/**
 * @title  WarpsArt
 * @author Hurls
 * @notice Renders the Warps visuals.
 */
library WarpsArt {
    /// @dev The semiperfect divisors of the 20 warps.
    function divisors() public pure returns (uint8[8] memory) {
        return [20, 4, 1, 0, 0, 0, 0, 0];
    }

    /// @dev The different color band sizes that we use for the art.
    function colorBands() public pure returns (uint8[7] memory) {
        return [10, 8, 6, 4, 2, 1, 0];
    }

    /// @dev The gradient increment steps.
    function gradients() public pure returns (uint8[7] memory) {
        return [0, 1, 2, 5, 8, 9, 10];
    }

    /// @dev Load a warp from storage and fill its current state settings.
    /// @param tokenId The id of the warp to fetch.
    /// @param warps The DB containing all warps.
    function getWarp(uint256 tokenId, IWarps.Warps storage warps) public view returns (IWarps.Warp memory warp) {
        IWarps.StoredWarp memory stored = warps.all[tokenId];

        return getWarp(tokenId, stored.divisorIndex, warps);
    }

    /// @dev Load a warp from storage and fill its current state settings.
    /// @param tokenId The id of the warp to fetch.
    /// @param divisorIndex The divisorindex to get.
    /// @param warps The DB containing all warps.
    function getWarp(uint256 tokenId, uint8 divisorIndex, IWarps.Warps storage warps)
        public
        view
        returns (IWarps.Warp memory warp)
    {
        IWarps.StoredWarp memory stored = warps.all[tokenId];
        stored.divisorIndex = divisorIndex; // Override in case we're fetching specific state.
        warp.stored = stored;

        // Set up the source of randomness + seed for this Warp.
        warp.seed = stored.seed;

        // Helpers
        warp.isRoot = divisorIndex == 0;
        warp.hasManyWarps = divisorIndex < 6;
        warp.composite = !warp.isRoot && divisorIndex < 7 ? stored.composites[divisorIndex - 1] : 0;

        // Token properties
        warp.colorBand = colorBandIndex(warp, divisorIndex);
        warp.gradient = gradientIndex(warp, divisorIndex);
        warp.warpsCount = divisors()[divisorIndex];
    }

    /// @dev Query the gradient of a given warp at a certain warp count.
    /// @param warp The warp we want to get the gradient for.
    /// @param divisorIndex The warp divisor in question.
    function gradientIndex(IWarps.Warp memory warp, uint8 divisorIndex) public pure returns (uint8) {
        uint256 n = Utilities.random(warp.seed, "gradient", 100);

        return divisorIndex == 0
            ? n < 20 ? uint8(1 + (n % 6)) : 0
            : divisorIndex < 6 ? warp.stored.gradients[divisorIndex - 1] : 0;
    }

    /// @dev Query the color band of a given warp at a certain warp count.
    /// @param warp The warp we want to get the color band for.
    /// @param divisorIndex The warp divisor in question.
    function colorBandIndex(IWarps.Warp memory warp, uint8 divisorIndex) public pure returns (uint8) {
        uint256 n = Utilities.random(warp.seed, "band", 10);

        return divisorIndex == 0
            ? (n > 5 ? 2 : 3) // Return either index 2 (6 colors) or 3 (4 colors)
            : divisorIndex < 6 ? warp.stored.colorBands[divisorIndex - 1] : 4;
    }

    /// @dev Generate indexes for the color slots of warp parents (up to the WarpColors.COLORS themselves).
    /// @param divisorIndex The current divisorIndex to query.
    /// @param warp The current warp to investigate.
    /// @param warps The DB containing all warps.
    function colorIndexes(uint8 divisorIndex, IWarps.Warp memory warp, IWarps.Warps storage warps)
        public
        view
        returns (uint256[] memory)
    {
        uint8[8] memory divisors_ = divisors();
        uint256 warpsCount = divisors_[divisorIndex];
        uint256 seed = warp.seed;
        uint8 colorBand = colorBands()[colorBandIndex(warp, divisorIndex)];
        uint8 gradient = gradients()[gradientIndex(warp, divisorIndex)];

        // If we're a composited warp, we choose colors only based on
        // the slots available in our parents. Otherwise,
        // we choose based on our available spectrum.
        uint256 possibleColorChoices = divisorIndex > 0 ? divisors_[divisorIndex - 1] * 2 : 10;

        // We initialize our index and select the first color
        uint256[] memory indexes = new uint256[](warpsCount);
        indexes[0] = Utilities.random(seed, possibleColorChoices);

        // If we have more than one warp, continue selecting colors
        if (warp.hasManyWarps) {
            if (gradient > 0) {
                // If we're a gradient warp, we select based on the color band looping around
                // the 20 possible colors
                for (uint256 i = 1; i < warpsCount;) {
                    indexes[i] = (indexes[0] + (i * gradient * colorBand / warpsCount) % colorBand) % 10;
                    unchecked {
                        ++i;
                    }
                }
            } else if (divisorIndex == 0) {
                // If we select initial non gradient colors, we just take random ones
                // available in our color band
                for (uint256 i = 1; i < warpsCount;) {
                    indexes[i] = (indexes[0] + Utilities.random(seed + i, colorBand)) % 10;
                    unchecked {
                        ++i;
                    }
                }
            } else {
                // If we have parent warps, we select our colors from their set
                for (uint256 i = 1; i < warpsCount;) {
                    indexes[i] = Utilities.random(seed + i, possibleColorChoices);
                    unchecked {
                        ++i;
                    }
                }
            }
        }

        // We resolve our color indexes through our parent tree until we reach the root warps
        if (divisorIndex > 0) {
            uint8 previousDivisor = divisorIndex - 1;

            // We already have our current warp, but need the our parent state color indices
            uint256[] memory parentIndexes = colorIndexes(previousDivisor, warp, warps);

            // We also need to fetch the colors of the warp that was composited into us
            IWarps.Warp memory composited = getWarp(warp.composite, previousDivisor, warps);
            uint256[] memory compositedIndexes = colorIndexes(previousDivisor, composited, warps);

            // Replace random indices with parent / root color indices
            uint8 count = divisors_[previousDivisor];

            // We always select the first color from our parent
            uint256 initialBranchIndex = indexes[0] % count;
            indexes[0] = indexes[0] < count ? parentIndexes[initialBranchIndex] : compositedIndexes[initialBranchIndex];

            // If we don't have a gradient, we continue resolving from our parent for the remaining warps
            if (gradient == 0) {
                for (uint256 i; i < warpsCount;) {
                    uint256 branchIndex = indexes[i] % count;
                    indexes[i] = indexes[i] < count ? parentIndexes[branchIndex] : compositedIndexes[branchIndex];

                    unchecked {
                        ++i;
                    }
                }
            } else {
                // If we have a gradient we base the remaining colors off our initial selection
                for (uint256 i = 1; i < warpsCount;) {
                    indexes[i] = (indexes[0] + (i * gradient * colorBand / warpsCount) % colorBand) % 10;

                    unchecked {
                        ++i;
                    }
                }
            }
        }

        return indexes;
    }

    /// @dev Fetch all colors of a given Warp.
    /// @param warp The warp to get colors for.
    /// @param warps The DB containing all warps.
    function colors(IWarps.Warp memory warp, IWarps.Warps storage warps)
        public
        view
        returns (string[] memory, uint256[] memory)
    {
        // A fully composited warp has no color.
        if (warp.stored.divisorIndex == 7) {
            string[] memory zeroColors = new string[](1);
            uint256[] memory zeroIndexes = new uint256[](1);
            zeroColors[0] = "000";
            zeroIndexes[0] = 999;
            return (zeroColors, zeroIndexes);
        }

        // Fetch the indices on the original color mapping.
        uint256[] memory indexes = colorIndexes(warp.stored.divisorIndex, warp, warps);

        // Map over to get the colors.
        string[] memory warpColors = new string[](indexes.length);
        string[10] memory allColors = WarpColors.colors();

        // Always set the first color.
        warpColors[0] = allColors[indexes[0]];

        // Resolve each additional check color via their index in WarpColors.COLORS.
        for (uint256 i = 1; i < indexes.length; i++) {
            warpColors[i] = allColors[indexes[i]];
        }

        return (warpColors, indexes);
    }

    /// @dev Get the number of warps we should display per row.
    /// @param warps The number of warps in the piece.
    function perRow(uint8 warps) public pure returns (uint8) {
        return warps == 80 ? 8 : warps >= 20 ? 4 : warps == 10 || warps == 4 ? 2 : 1;
    }

    /// @dev Get the X-offset for positioning warp horizontally.
    /// @param warps The number of warps in the piece.
    function rowX(uint8 warps) public pure returns (uint16) {
        if (warps == 2) {
            return 310; // Adjusted value to center two warps horizontally
        }
        return warps <= 1 ? 286 : warps == 5 ? 304 : warps == 10 || warps == 4 ? 268 : 196;
    }

    /// @dev Get the Y-offset for positioning warp vertically.
    /// @param warps The number of warps in the piece.
    function rowY(uint8 warps) public pure returns (uint16) {
        if (warps == 2) {
            return 270; // Adjusted value to center two warps vertically
        }
        return warps > 4 ? 160 : warps == 4 ? 268 : warps > 1 ? 304 : 286;
    }

    /// @dev Generate the SVG code for all warps in a given token.
    /// @param data The data object containing rendering settings.
    function generateWarps(WarpRenderData memory data) public pure returns (bytes memory) {
        bytes memory warpsBytes;

        uint8 warpsCount = data.count;
        for (uint8 i; i < warpsCount; i++) {
            // Compute row settings.
            data.indexInRow = i % data.perRow;
            data.isNewRow = data.indexInRow == 0 && i > 0;

            // Compute offsets.
            if (data.isNewRow) data.rowY += data.spaceY;
            if (data.isNewRow && data.indent) {
                if (i == 0) {
                    data.rowX += data.spaceX / 2;
                }

                if (i % (data.perRow * 2) == 0) {
                    data.rowX -= data.spaceX / 2;
                } else {
                    data.rowX += data.spaceX / 2;
                }
            }
            string memory translateX = Utilities.uint2str(data.rowX + data.indexInRow * data.spaceX);
            string memory translateY = Utilities.uint2str(data.rowY);
            string memory color = data.colors[i];

            // Render the current   .
            warpsBytes = abi.encodePacked(
                warpsBytes,
                abi.encodePacked(
                    '<g transform="translate(',
                    translateX,
                    ", ",
                    translateY,
                    ')">',
                    '<g transform="translate(3, 3) scale(',
                    data.scale,
                    ')">',
                    // Outer layer (color)
                    '<path d="M15 26.264c1.271 0 4.012 4.144 5.207 3.703 1.194-.441.668-5.403 1.643-6.233.974-.83 5.698.558 6.334-.56.636-1.117-2.91-4.576-2.69-5.847.221-1.27 4.72-3.29 4.498-4.56-.22-1.271-5.127-1.607-5.763-2.725-.636-1.117 1.53-5.597.556-6.427-.974-.83-4.945 2.114-6.14 1.672C17.45 4.846 16.272 0 15 0c-1.272 0-2.45 4.846-3.645 5.287-1.195.442-5.166-2.502-6.14-1.672-.974.83 1.192 5.31.556 6.427C5.136 11.16.23 11.496.008 12.767c-.22 1.27 4.277 3.29 4.497 4.56.221 1.271-3.325 4.73-2.689 5.847.636 1.118 5.36-.27 6.334.56.974.83.448 5.791 1.643 6.233 1.196.441 3.936-3.703 5.207-3.703Z" fill="#',
                    color,
                    '"/>',
                    // First black layer
                    '<path d="M14.999 24.216c1.04 0 3.283 3.39 4.26 3.03.978-.361.547-4.421 1.345-5.1.797-.679 4.662.456 5.182-.458.52-.915-2.381-3.744-2.2-4.784.18-1.04 3.86-2.691 3.68-3.731-.181-1.04-4.196-1.315-4.716-2.23-.52-.913 1.253-4.58.456-5.258-.797-.679-4.047 1.73-5.025 1.368-.977-.361-1.941-4.326-2.982-4.326-1.04 0-2.004 3.965-2.982 4.326-.977.361-4.227-2.047-5.024-1.368-.797.678.976 4.345.456 5.259-.52.914-4.535 1.19-4.716 2.229-.18 1.04 3.5 2.691 3.68 3.731.18 1.04-2.72 3.87-2.2 4.784.52.914 4.385-.22 5.182.458.797.678.367 4.738 1.344 5.1.978.36 3.22-3.03 4.26-3.03Z" fill="#000"/>',
                    // Middle layer (color)
                    '<path d="M14.998 22.168c.81 0 2.553 2.637 3.314 2.357.76-.281.425-3.44 1.046-3.967.62-.528 3.625.355 4.03-.356.405-.712-1.852-2.912-1.711-3.72.14-.81 3.003-2.094 2.862-2.903-.14-.809-3.263-1.023-3.668-1.734-.404-.711.975-3.562.355-4.09S18.078 9.1 17.318 8.819c-.76-.28-1.51-3.364-2.32-3.364-.809 0-1.558 3.083-2.319 3.364-.76.281-3.288-1.592-3.907-1.064-.62.528.758 3.379.354 4.09-.405.711-3.527.925-3.668 1.734-.14.809 2.722 2.093 2.862 2.902.14.809-2.116 3.01-1.711 3.72.404.712 3.41-.171 4.03.357.62.528.286 3.685 1.046 3.966.76.281 2.505-2.356 3.314-2.356Z" fill="#',
                    color,
                    '"/>',
                    // Inner black layer
                    '<path d="M15.005 20.12c.579 0 1.824 1.884 2.367 1.683.543-.2.304-2.456.747-2.833.443-.377 2.59.254 2.88-.255.288-.508-1.323-2.08-1.223-2.657.1-.578 2.145-1.495 2.044-2.073-.1-.578-2.33-.73-2.62-1.238-.288-.508.696-2.545.254-2.922-.443-.377-2.248.96-2.792.76-.543-.2-1.078-2.403-1.656-2.403-.578 0-1.114 2.202-1.657 2.403-.543.2-2.348-1.137-2.791-.76-.443.377.542 2.414.253 2.922-.29.508-2.52.66-2.62 1.238-.1.578 1.944 1.495 2.044 2.073.1.578-1.511 2.15-1.222 2.657.289.509 2.437-.122 2.88.255.442.377.203 2.632.746 2.833.543.2 1.789-1.683 2.367-1.683Z" fill="#000"/>',
                    // Inner layer (color)
                    '<path d="M15 18.584c.404 0 1.276 1.319 1.656 1.178.38-.14.213-1.719.523-1.983.31-.264 1.813.177 2.015-.178.202-.356-.926-1.456-.855-1.86.07-.405 1.5-1.047 1.43-1.451-.07-.405-1.63-.512-1.833-.867-.203-.356.487-1.782.177-2.046-.31-.264-1.574.673-1.954.532-.38-.14-.755-1.682-1.16-1.682-.404 0-.78 1.542-1.16 1.682-.38.141-1.643-.796-1.953-.532-.31.264.38 1.69.177 2.046-.202.355-1.764.462-1.834.867-.07.404 1.36 1.046 1.431 1.45.07.405-1.058 1.505-.856 1.86.203.356 1.706-.085 2.016.179.31.264.142 1.843.523 1.983.38.14 1.252-1.178 1.656-1.178Z" fill="#',
                    color,
                    '"/>',
                    "</g>",
                    "</g>"
                )
            );
        }

        return warpsBytes;
    }

    /// @dev Collect relevant rendering data for easy access across functions.
    /// @param warp Our current warp loaded from storage.
    /// @param warps The DB containing all warps.
    function collectRenderData(IWarps.Warp memory warp, IWarps.Warps storage warps)
        public
        view
        returns (WarpRenderData memory data)
    {
        // Carry through base settings.
        data.warp = warp;
        data.isBlack = warp.stored.divisorIndex == 7;
        data.count = data.isBlack ? 1 : divisors()[warp.stored.divisorIndex];

        // Compute colors and indexes.
        (string[] memory colors_, uint256[] memory colorIndexes_) = colors(warp, warps);
        data.gridColor = "#000000";
        data.canvasColor = "#000000";
        data.colorIndexes = colorIndexes_;
        data.colors = colors_;

        // Compute positioning data.
        data.scale = data.count > 20 ? "1.2" : data.count > 1 ? "2" : "3";
        data.spaceX = data.count == 80 ? 36 : 72;
        data.spaceY = data.count > 20 ? 36 : 72;
        data.perRow = perRow(data.count);
        data.indent = data.count == 40;
        data.rowX = rowX(data.count);
        data.rowY = rowY(data.count);
    }

    /// @dev Generate the SVG code for rows in the 8x10 Warps grid.
    function generateGridRow() public pure returns (bytes memory) {
        bytes memory row;
        for (uint256 i; i < 8; i++) {
            row = abi.encodePacked(row, '<use href="#square" x="', Utilities.uint2str(196 + i * 36), '" y="160"/>');
        }
        return row;
    }

    /// @dev Generate the SVG code for the entire 8x10 Warps grid.
    function generateGrid() public pure returns (bytes memory) {
        bytes memory grid;
        for (uint256 i; i < 10; i++) {
            grid = abi.encodePacked(grid, '<use href="#row" y="', Utilities.uint2str(i * 36), '"/>');
        }

        return abi.encodePacked('<g id="grid" x="196" y="160">', grid, "</g>");
    }

    /// @dev Generate the complete SVG code for a given Warp.
    /// @param warp The warp to render.
    /// @param warps The DB containing all warps.
    function generateSVG(IWarps.Warp memory warp, IWarps.Warps storage warps) public view returns (bytes memory) {
        WarpRenderData memory data = collectRenderData(warp, warps);

        return abi.encodePacked(
            "<svg ",
            'viewBox="0 0 680 680" ',
            'fill="none" xmlns="http://www.w3.org/2000/svg" ',
            'style="width:100%;background:black;"',
            ">",
            "<defs>",
            '<rect id="square" width="36" height="36" stroke="',
            data.gridColor,
            '"></rect>',
            '<g id="row">',
            generateGridRow(),
            "</g>" "</defs>",
            '<rect width="680" height="680" fill="black"/>',
            '<rect x="188" y="152" width="304" height="376" fill="',
            data.canvasColor,
            '"/>',
            generateGrid(),
            generateWarps(data),
            "</svg>"
        );
    }

    /*────────────────────────── Palette Support ─────────────────────────*/

    /// @dev Convert a packed uint24 RGB into 6-character hex string (no prefix).
    function _uint24ToHex(uint24 value) internal pure returns (string memory) {
        bytes16 symbols = "0123456789abcdef";
        bytes memory buffer = new bytes(6);
        for (uint256 i; i < 6; ++i) {
            buffer[5 - i] = symbols[value & 0xF];
            value >>= 4;
        }
        return string(buffer);
    }

    /// @notice Generate SVG strictly using provided palette colours.
    /// @param warp The warp to render.
    /// @param warps Global warps storage.
    /// @param palette Array of packed uint24 RGB colours.
    function generateSVGWithPalette(IWarps.Warp memory warp, IWarps.Warps storage warps, uint24[] memory palette)
        public
        view
        returns (bytes memory)
    {
        WarpRenderData memory data = collectRenderData(warp, warps);

        // Build colour strings cycling through palette.
        uint256 len = data.count;
        string[] memory custom = new string[](len);
        for (uint256 i; i < len; ++i) {
            custom[i] = _uint24ToHex(palette[i % palette.length]);
        }
        data.colors = custom;

        return abi.encodePacked(
            "<svg ",
            'viewBox="0 0 680 680" ',
            'fill="none" xmlns="http://www.w3.org/2000/svg" ',
            'style="width:100%;background:black;"',
            ">",
            "<defs>",
            '<rect id="square" width="36" height="36" stroke="',
            data.gridColor,
            '"></rect>',
            '<g id="row">',
            generateGridRow(),
            "</g>" "</defs>",
            '<rect width="680" height="680" fill="black"/>',
            '<rect x="188" y="152" width="304" height="376" fill="',
            data.canvasColor,
            '"/>',
            generateGrid(),
            generateWarps(data),
            "</svg>"
        );
    }
}

/// @dev Bag holding all data relevant for rendering.
struct WarpRenderData {
    IWarps.Warp warp;
    uint256[] colorIndexes;
    string[] colors;
    string canvasColor;
    string gridColor;
    string duration;
    string scale;
    uint32 seed;
    uint16 rowX;
    uint16 rowY;
    uint8 count;
    uint8 spaceX;
    uint8 spaceY;
    uint8 perRow;
    uint8 indexInRow;
    uint8 isIndented;
    bool isNewRow;
    bool isBlack;
    bool indent;
    bool isStatic;
}
