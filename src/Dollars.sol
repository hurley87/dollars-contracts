// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IArrows.sol";
import "./interfaces/IArrowsEdition.sol";
import "./libraries/ArrowsArt.sol";
import "./libraries/ArrowsMetadata.sol";
import "./libraries/Utilities.sol";
import "./standards/ARROWS721.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title  Dollars
 * @author Hurls
 * @notice Up and to the right.
 */
contract Dollars is IArrows, ARROWS721, Ownable {
    event MintPriceUpdated(uint256 newPrice);
    event MintLimitUpdated(uint8 newLimit);
    event WinnerPercentageUpdated(uint8 newPercentage);
    event PrizeClaimed(uint256 tokenId, address winner, uint256 amount);
    event OwnerShareWithdrawn(uint256 amount);
    event PrizePoolUpdated(uint256 totalDeposited, uint256 totalWithdrawn);
    event EmergencyWithdrawn(uint256 amount);
    event TokensMinted(address indexed recipient, uint256 startTokenId, uint256 count);
    event TokensComposited(uint256 indexed keptTokenId, uint256 indexed burnedTokenId);
    event TokenBurned(uint256 indexed tokenId, address indexed burner);

    uint8 public mintLimit = 4;
    uint256 public constant MAX_COMPOSITE_LEVEL = 5;
    uint256 public mintPrice = 0.001 ether;
    uint256 public tokenMintId = 0;

    /// @dev We use this database for persistent storage.
    Arrows _arrowsData;

    // Prize pool state
    struct PrizePool {
        uint8 winnerPercentage; // Percentage for winner (1-99)
        uint32 lastWinnerClaim; // Timestamp of last winner claim
        uint256 totalDeposited; // Total ETH ever deposited
        uint256 totalWithdrawn; // Total ETH withdrawn by owner
    }

    PrizePool public prizePool;

    /// @notice Get the total amount deposited in the prize pool
    /// @return The total amount deposited
    function getTotalDeposited() public view returns (uint256) {
        return prizePool.totalDeposited;
    }

    /// @notice Get the total amount withdrawn by the owner
    /// @return The total amount withdrawn
    function getTotalWithdrawn() public view returns (uint256) {
        return prizePool.totalWithdrawn;
    }

    /// @notice Get the winner percentage from the prize pool
    /// @return The winner percentage
    function getWinnerPercentage() public view returns (uint8) {
        return prizePool.winnerPercentage;
    }

    // Store token metadata directly instead of using epochs
    struct TokenMetadata {
        uint256 seed; // The final seed used for randomization
        uint8[5] colorBands; // Color band values
        uint8[5] gradients; // Gradient values
    }

    mapping(uint256 => TokenMetadata) private _tokenMetadata;

    /// @dev Initializes the Arrows Originals contract and links the Edition contract.
    constructor() Ownable() {
        _arrowsData.minted = 0;
        _arrowsData.burned = 0;
        prizePool.winnerPercentage = 60; // Default 60% for winner
        prizePool.lastWinnerClaim = 0;
    }

    /// @notice Update the mint price
    /// @param newPrice The new price in ETH
    function updateMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    /// @notice Update the mint limit
    /// @param newLimit The new limit of tokens per mint
    function updateMintLimit(uint8 newLimit) external onlyOwner {
        require(newLimit > 0 && newLimit <= 100, "Invalid limit");
        mintLimit = newLimit;
        emit MintLimitUpdated(newLimit);
    }

    /// @notice Update the winner's percentage of the prize pool
    /// @param newPercentage The new percentage (1-99)
    function updateWinnerPercentage(uint8 newPercentage) external onlyOwner {
        require(newPercentage > 0 && newPercentage < 100, "Invalid percentage");
        require(block.timestamp >= uint256(prizePool.lastWinnerClaim) + 1 days, "Too soon after winner claim");
        prizePool.winnerPercentage = newPercentage;
        emit WinnerPercentageUpdated(newPercentage);
    }

    /// @notice Generate randomness for a token at mint time
    /// @param tokenId The token ID to generate randomness for
    function _generateTokenRandomness(uint256 tokenId) internal {
        uint256 seed = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, tokenId, msg.sender, _arrowsData.minted))
        ) % type(uint128).max;

        // Store the seed for this token
        _tokenMetadata[tokenId].seed = seed;

        // Extract non-contiguous bytes to reduce correlation
        uint8 n1 = uint8(seed & 0xFF); // byte 0
        uint8 n2 = uint8((seed >> 56) & 0xFF); // byte 7

        // Scale to maintain original rarity distributions
        uint8 scaledN1 = uint8((uint256(n1) * 120) / 255);
        uint8 scaledN2 = uint8((uint256(n2) * 100) / 255);

        // Apply thresholds using scaled values
        uint8 colorBand = scaledN1 > 20
            ? 0
            : scaledN1 > 10 ? 1 : scaledN1 > 5 ? 2 : scaledN1 > 2 ? 3 : scaledN1 > 1 ? 4 : scaledN1 > 0 ? 5 : 6;

        uint8 gradient = scaledN2 < 20 ? uint8(1 + (scaledN2 % 6)) : 0;

        // Store the initial values
        _arrowsData.all[tokenId].colorBands[0] = colorBand;
        _arrowsData.all[tokenId].gradients[0] = gradient;
    }

    /// @notice Mint new Arrows tokens
    /// @param recipient The address to receive the tokens
    function mint(address recipient) external payable {
        require(recipient != address(0), "Invalid recipient");

        // Check if enough ETH was sent
        require(msg.value >= mintPrice * mintLimit, "Insufficient payment");

        // Update prize pool
        prizePool.totalDeposited += msg.value;
        emit PrizePoolUpdated(prizePool.totalDeposited, prizePool.totalWithdrawn);

        uint256 startTokenId = tokenMintId;

        // Mint the tokens
        for (uint256 i; i < mintLimit;) {
            uint256 id = tokenMintId++;

            StoredArrow storage arrow = _arrowsData.all[id];
            arrow.seed = uint16(id);
            arrow.divisorIndex = 0;

            // Generate immediate randomness for this token
            _generateTokenRandomness(id);

            _safeMint(recipient, id);

            unchecked {
                ++i;
            }
        }

        // Keep track of how many arrows have been minted
        unchecked {
            _arrowsData.minted += uint32(mintLimit);
        }

        emit TokensMinted(recipient, startTokenId, mintLimit);
    }

    /// @notice Composite one token into another, mixing visuals and reducing arrow count
    /// @param tokenId The token ID to keep alive (its visual will change)
    /// @param burnId The token ID to composite into the kept token
    function composite(uint256 tokenId, uint256 burnId) external {
        _composite(tokenId, burnId);
        unchecked {
            ++_arrowsData.burned;
        }
        emit TokensComposited(tokenId, burnId);
    }

    /// @notice Burn a single arrow token without compositing
    /// @param tokenId The token ID to burn
    /// @dev This is a common purpose burn method that does not affect other tokens
    function burn(uint256 tokenId) external {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotAllowed();
        }

        _burn(tokenId);
        unchecked {
            ++_arrowsData.burned;
        }
        emit TokenBurned(tokenId, msg.sender);
    }

    /// @notice Get the metadata URI for a token
    /// @param tokenId The token ID to get metadata for
    /// @return The metadata URI string
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        return ArrowsMetadata.tokenURI(tokenId, _arrowsData);
    }

    /// @dev Get arrow with the stored seed instead of epoch-based randomness
    function _getArrowWithSeed(uint256 tokenId) internal view returns (IArrows.Arrow memory) {
        IArrows.Arrow memory arrow = ArrowsArt.getArrow(tokenId, _arrowsData);

        // Override the seed with our stored seed
        if (_tokenMetadata[tokenId].seed != 0) {
            arrow.seed = _tokenMetadata[tokenId].seed;
        }

        return arrow;
    }

    /// @dev Composite one token into to another and burn it.
    /// @param tokenId The token ID to keep. Its art and arrow-count will change.
    /// @param burnId The token ID to burn in the process.
    function _composite(uint256 tokenId, uint256 burnId) internal {
        (StoredArrow storage toKeep,, uint8 divisorIndex) = _tokenOperation(tokenId, burnId);

        uint8 nextDivisor = divisorIndex + 1;

        // We only need to breed band + gradient up until 4-Arrows.
        if (divisorIndex < 5) {
            (uint8 gradient, uint8 colorBand) = _compositeGenes(tokenId, burnId);

            toKeep.colorBands[divisorIndex] = colorBand;
            toKeep.gradients[divisorIndex] = gradient;
        }

        // Composite our arrow
        toKeep.composites[divisorIndex] = uint16(burnId);
        toKeep.divisorIndex = nextDivisor;

        // Generate new randomness for the composited token
        uint256 newSeed = uint256(
            keccak256(abi.encodePacked(_tokenMetadata[tokenId].seed, _tokenMetadata[burnId].seed, block.timestamp))
        ) % type(uint128).max;

        _tokenMetadata[tokenId].seed = newSeed;

        // Perform the burn.
        _burn(burnId);

        // Notify DAPPs about the Composite.
        emit Composite(tokenId, burnId, ArrowsArt.DIVISORS()[toKeep.divisorIndex]);
        emit MetadataUpdate(tokenId);
    }

    /// @dev Composite the gradient and colorBand settings.
    /// @param tokenId The token ID to keep.
    /// @param burnId The token ID to burn.
    function _compositeGenes(uint256 tokenId, uint256 burnId) internal view returns (uint8 gradient, uint8 colorBand) {
        Arrow memory keeper = _getArrowWithSeed(tokenId);
        Arrow memory burner = _getArrowWithSeed(burnId);

        // Pseudorandom gene manipulation.
        uint256 randomizer = uint256(keccak256(abi.encodePacked(keeper.seed, burner.seed)));

        // If at least one token has a gradient, we force it in ~20% of cases.
        gradient = Utilities.random(randomizer, 100) > 80
            ? randomizer % 2 == 0
                ? Utilities.minGt0(keeper.gradient, burner.gradient)
                : Utilities.max(keeper.gradient, burner.gradient)
            : Utilities.min(keeper.gradient, burner.gradient);

        // We breed the lower end average color band when breeding.
        colorBand = Utilities.avg(keeper.colorBand, burner.colorBand);
    }

    /// @dev Make sure this is a valid request to composite/switch a token pair.
    /// @param tokenId The token ID to keep.
    /// @param burnId The token ID to burn.
    function _tokenOperation(uint256 tokenId, uint256 burnId)
        internal
        view
        returns (StoredArrow storage toKeep, StoredArrow storage toBurn, uint8 divisorIndex)
    {
        toKeep = _arrowsData.all[tokenId];
        toBurn = _arrowsData.all[burnId];
        divisorIndex = toKeep.divisorIndex;

        require(
            _isApprovedOrOwner(msg.sender, tokenId) && _isApprovedOrOwner(msg.sender, burnId)
                && divisorIndex == toBurn.divisorIndex && tokenId != burnId && divisorIndex <= MAX_COMPOSITE_LEVEL,
            "Invalid composite operation"
        );
    }

    /// @notice Withdraw the owner's share of the prize pool
    /// @dev Only callable by the contract owner
    /// @dev Withdraws the available owner share based on total deposits and withdrawals
    function withdrawOwnerShare() external onlyOwner {
        uint256 availableToWithdraw = getAvailableOwnerWithdrawal();
        require(availableToWithdraw > 0, "No new funds to withdraw");

        (bool success,) = payable(owner()).call{value: availableToWithdraw}("");
        require(success, "Transfer failed");

        prizePool.totalWithdrawn += availableToWithdraw;
        emit OwnerShareWithdrawn(availableToWithdraw);
    }

    /// @notice Claim the prize for a winning token
    /// @param tokenId The token ID to check and claim
    /// @dev Verifies token ownership, winning status, and available prize pool
    /// @dev Burns the winning token and transfers the prize to the winner
    function claimPrize(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(isWinningToken(tokenId), "Not a winning token");

        uint256 winnerShare = getWinnerShare();
        uint256 availableBalance = getAvailablePrizePool();
        require(winnerShare > 0 && winnerShare <= availableBalance, "No prize available");

        prizePool.totalDeposited -= winnerShare;
        prizePool.lastWinnerClaim = uint32(block.timestamp);
        _burn(tokenId);
        unchecked {
            ++_arrowsData.burned;
        }

        (bool success,) = payable(msg.sender).call{value: winnerShare}("");
        require(success, "Transfer failed");

        emit PrizeClaimed(tokenId, msg.sender, winnerShare);
    }

    /// @notice Emergency withdrawal of all contract balance
    /// @dev Only callable by the contract owner
    /// @dev Used in case of emergency to recover all funds
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");

        emit EmergencyWithdrawn(balance);
    }

    /// @notice Get the current available prize pool balance
    /// @return The current contract balance
    function getAvailablePrizePool() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Calculate the owner's share of the prize pool
    /// @return The owner's share based on total deposits and winner percentage
    function getOwnerShare() public view returns (uint256) {
        unchecked {
            return (prizePool.totalDeposited * (100 - prizePool.winnerPercentage)) / 100;
        }
    }

    /// @notice Calculate the winner's share of the prize pool
    /// @return The winner's share based on total deposits and winner percentage
    function getWinnerShare() public view returns (uint256) {
        unchecked {
            return (prizePool.totalDeposited * prizePool.winnerPercentage) / 100;
        }
    }

    /// @notice Calculate the available amount for owner withdrawal
    /// @return The amount available for owner to withdraw
    function getAvailableOwnerWithdrawal() public view returns (uint256) {
        uint256 ownerShare = getOwnerShare();
        return ownerShare > prizePool.totalWithdrawn ? ownerShare - prizePool.totalWithdrawn : 0;
    }

    /// @notice Check if a token is a winning token
    /// @param tokenId The token ID to check
    /// @return bool True if the token is a winner, false otherwise
    /// @dev A token is considered a winner if it has exactly 1 arrow and its first color is "018A08"
    function isWinningToken(uint256 tokenId) public view returns (bool) {
        if (!_exists(tokenId)) return false;

        Arrow memory arrow = _getArrowWithSeed(tokenId);
        if (arrow.arrowsCount != 1) return false;

        (string[] memory tokenColors,) = ArrowsArt.colors(arrow, _arrowsData);
        return keccak256(abi.encodePacked(tokenColors[0])) == keccak256(abi.encodePacked("018A08"));
    }
}
