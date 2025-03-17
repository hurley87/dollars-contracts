// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IArrows {
    struct StoredArrow {
        uint16[6] composites; // The tokenIds that were composited into this one
        uint8[5] colorBands; // The length of the used color band in percent
        uint8[5] gradients; // Gradient settings for each generation
        uint8 divisorIndex; // Easy access to next / previous divisor
        uint16 seed; // A unique identifier to enable swapping
        uint24 day; // The days since token was created
        uint32 epoch; // The epoch when this token was created (legacy field, not used for randomness)
    }

    struct Arrow {
        StoredArrow stored; // We carry over the arrow from storage
        uint256 seed; // The instantiated seed for pseudo-randomisation
        uint8 arrowsCount; // How many arrows this token has
        bool hasManyArrows; // Whether the arrow has many arrows
        uint16 composite; // The parent tokenId that was composited into this one
        bool isRoot; // Whether it has no parents (80 arrows)
        uint8 colorBand; // 100%, 50%, 25%, 12.5%, 6.25%, 5%, 1.25%
        uint8 gradient; // Linearly through the colorBand [1, 2, 3]
        uint8 direction; // Animation direction
        uint8 speed; // Animation speed
    }

    struct Epoch {
        bool committed;
        bool revealed;
        uint64 revealBlock;
        uint128 randomness;
    }

    struct Arrows {
        mapping(uint256 => StoredArrow) all; // All arrows
        mapping(uint256 => Epoch) epochs; // Epoch data for randomness
        uint32 minted; // The number of arrows editions that have been migrated
        uint32 burned; // The number of tokens that have been burned
        uint32 day0; // Marks the start of this journey
        uint32 currentEpoch; // Current epoch number
    }

    event Sacrifice(uint256 indexed burnedId, uint256 indexed tokenId);

    event Composite(uint256 indexed tokenId, uint256 indexed burnedId, uint8 indexed arrows);

    event Infinity(uint256 indexed tokenId, uint256[] indexed burnedIds);

    event NewEpoch(uint256 indexed epoch, uint256 revealBlock);

    error NotAllowed();
    error InvalidTokenCount();
    error BlackArrow__InvalidArrow();
}
