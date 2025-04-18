// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IArrows.sol";
import "./interfaces/IArrowsEdition.sol";
import "./libraries/ArrowsArt.sol";
import "./libraries/ArrowsMetadata.sol";
import "./libraries/EightyColors.sol";
import "./libraries/Utilities.sol";
import "./standards/ARROWS721.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/security/Pausable.sol";

/**
 * @title  Dollars
 * @author Hurls
 * @notice Up and to the right.
 */
contract Dollars is IArrows, ARROWS721, Ownable, Pausable {
    event MintPriceUpdated(uint256 newPrice);
    event MintLimitUpdated(uint8 newLimit);
    event PrizeClaimed(uint256 tokenId, address winner, uint256 amount);
    event PrizePoolUpdated(uint256 totalDeposited);
    event EmergencyWithdrawn(uint256 amount);
    event TokensMinted(address indexed recipient, uint256 startTokenId, uint256 count);
    event TokensComposited(uint256 indexed keptTokenId, uint256 indexed burnedTokenId);
    event TokenBurned(uint256 indexed tokenId, address indexed burner);
    event WinningColorIndexUpdated(uint8 newIndex);
    event PaymentTokenSet(address indexed tokenAddress, uint256 mintPrice);
    event OwnerMintSharePercentageUpdated(uint8 newPercentage);
    event WinnerClaimPercentageUpdated(uint8 newPercentage);
    event WinningColorSet(string colorHex, uint8 colorIndex);
    event FreeMintUsed(address indexed recipient);
    event TokensDeposited(address indexed sender, uint256 amount);
    event ContractPaused(address indexed pauser);
    event ContractUnpaused(address indexed unpauser);

    uint8 public mintLimit = 4;
    uint256 public constant MAX_COMPOSITE_LEVEL = 5;
    uint256 public mintPrice;
    uint256 public tokenMintId = 0;
    IERC20 public paymentToken;

    /// @dev We use this database for persistent storage.
    Arrows _arrowsData;

    // Prize pool state
    struct PrizePool {
        uint32 lastWinnerClaim;
        uint256 totalDeposited;
        uint256 actualAvailable; // Tracks the real available amount after owner shares
    }

    PrizePool public prizePool;
    uint8 public winningColorIndex;
    uint8 public ownerMintSharePercentage;
    uint8 public winnerClaimPercentage;

    // Track addresses that have already used their free mint
    mapping(address => bool) public hasUsedFreeMint;

    // Store token metadata directly instead of using epochs
    struct TokenMetadata {
        uint256 seed; // The final seed used for randomization
        uint8[5] colorBands; // Color band values - Note: These seem unused now, consider removal?
        uint8[5] gradients; // Gradient values - Note: These seem unused now, consider removal?
    }

    mapping(uint256 => TokenMetadata) private _tokenMetadata;

    /// @notice Get the total amount deposited in the prize pool
    /// @return The total amount deposited
    function getTotalDeposited() public view returns (uint256) {
        return prizePool.totalDeposited;
    }

    /// @notice Get the actual available amount in the prize pool for prizes
    /// @return The actual available amount for prizes
    function getActualAvailable() public view returns (uint256) {
        return prizePool.actualAvailable;
    }

    /// @dev Initializes the Arrows Originals contract and links the Edition contract.
    constructor() Ownable() {
        _arrowsData.minted = 0;
        _arrowsData.burned = 0;
        prizePool.lastWinnerClaim = 0;
        prizePool.actualAvailable = 0;
        winningColorIndex = 23;
        ownerMintSharePercentage = 40;
        winnerClaimPercentage = 20;
    }

    /// @notice Pauses the contract, preventing certain operations
    /// @dev Can only be called by the contract owner
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /// @notice Unpauses the contract, allowing operations to resume
    /// @dev Can only be called by the contract owner
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    /// @notice Allow users to deposit tokens to the contract for minting
    /// @param amount The amount of tokens to deposit
    function depositTokens(uint256 amount) external whenNotPaused {
        require(address(paymentToken) != address(0), "Payment token not set");
        require(amount > 0, "Amount must be greater than 0");

        // Transfer tokens from the user to this contract
        bool success = paymentToken.transferFrom(msg.sender, address(this), amount);
        require(success, "ERC20 transfer failed");

        // Add the full amount to both prize pool trackers
        prizePool.totalDeposited += amount;
        prizePool.actualAvailable += amount;

        emit TokensDeposited(msg.sender, amount);
        emit PrizePoolUpdated(prizePool.totalDeposited);
    }

    /// @notice Update the mint price (in terms of the payment token)
    /// @param newPrice The new price in the smallest unit of the payment token
    function updateMintPrice(uint256 newPrice) external onlyOwner {
        require(address(paymentToken) != address(0), "Payment token not set");
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    /// @notice Sets the ERC20 token used for payments and its mint price.
    /// @param _tokenAddress The address of the ERC20 token contract.
    /// @param _mintPrice The price to mint tokens, in the smallest unit of the ERC20 token.
    function setPaymentToken(address _tokenAddress, uint256 _mintPrice) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        paymentToken = IERC20(_tokenAddress);
        mintPrice = _mintPrice;
        emit PaymentTokenSet(_tokenAddress, _mintPrice);
        emit MintPriceUpdated(_mintPrice);
    }

    /// @notice Update the mint limit
    /// @param newLimit The new limit of tokens per mint
    function updateMintLimit(uint8 newLimit) external onlyOwner {
        require(newLimit > 0 && newLimit <= 100, "Invalid limit");
        mintLimit = newLimit;
        emit MintLimitUpdated(newLimit);
    }

    /// @notice Update the owner's percentage share received on each mint
    /// @param newPercentage The new percentage (0-99)
    function updateOwnerMintSharePercentage(uint8 newPercentage) external onlyOwner {
        require(newPercentage < 100, "Percentage must be < 100");
        ownerMintSharePercentage = newPercentage;
        emit OwnerMintSharePercentageUpdated(newPercentage);
    }

    /// @notice Update the winner's percentage share of the current prize pool upon claim
    /// @param newPercentage The new percentage (1-100)
    function updateWinnerClaimPercentage(uint8 newPercentage) external onlyOwner {
        require(newPercentage > 0 && newPercentage <= 100, "Percentage must be 1-100");
        winnerClaimPercentage = newPercentage;
        emit WinnerClaimPercentageUpdated(newPercentage);
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

    /// @notice Mint new Arrows tokens using the specified ERC20 payment token
    /// @param recipient The address to receive the tokens
    function mint(address recipient) external whenNotPaused {
        require(address(paymentToken) != address(0), "Payment token not set");
        require(recipient != address(0), "Invalid recipient");

        uint256 requiredAmount = mintPrice * mintLimit;
        require(requiredAmount > 0, "Mint price cannot be zero");

        // Process payment by default
        uint256 allowance = paymentToken.allowance(msg.sender, address(this));
        require(allowance >= requiredAmount, "Check allowance");
        bool success = paymentToken.transferFrom(msg.sender, address(this), requiredAmount);
        require(success, "ERC20 transfer failed (minter -> contract)");

        uint256 ownerShareAmount = (requiredAmount * ownerMintSharePercentage) / 100;
        uint256 prizePoolAmount = requiredAmount - ownerShareAmount;

        if (ownerShareAmount > 0) {
            bool ownerTransferSuccess = paymentToken.transfer(owner(), ownerShareAmount);
            require(ownerTransferSuccess, "ERC20 transfer failed (contract -> owner)");
        }

        // Add total amount to totalDeposited (for test compatibility)
        prizePool.totalDeposited += requiredAmount;
        // Track the actual available amount separately
        prizePool.actualAvailable += prizePoolAmount;
        emit PrizePoolUpdated(prizePool.totalDeposited);

        uint256 startTokenId = tokenMintId;

        for (uint256 i; i < mintLimit;) {
            uint256 id = tokenMintId++;

            StoredArrow storage arrow = _arrowsData.all[id];
            arrow.seed = uint16(id);
            arrow.divisorIndex = 0;

            _generateTokenRandomness(id);

            _safeMint(recipient, id);

            unchecked {
                ++i;
            }
        }

        unchecked {
            _arrowsData.minted += uint32(mintLimit);
        }

        emit TokensMinted(recipient, startTokenId, mintLimit);
    }

    /// @notice Mint new Arrows tokens with a free mint if available
    /// @param recipient The address to receive the tokens
    function freeMint(address recipient) external whenNotPaused {
        require(address(paymentToken) != address(0), "Payment token not set");
        require(recipient != address(0), "Invalid recipient");
        require(!hasUsedFreeMint[msg.sender], "Free mint already used");

        // Mark that this address has used its free mint
        hasUsedFreeMint[msg.sender] = true;
        emit FreeMintUsed(msg.sender);

        uint256 startTokenId = tokenMintId;

        for (uint256 i; i < mintLimit;) {
            uint256 id = tokenMintId++;

            StoredArrow storage arrow = _arrowsData.all[id];
            arrow.seed = uint16(id);
            arrow.divisorIndex = 0;

            _generateTokenRandomness(id);

            _safeMint(recipient, id);

            unchecked {
                ++i;
            }
        }

        unchecked {
            _arrowsData.minted += uint32(mintLimit);
        }

        emit TokensMinted(recipient, startTokenId, mintLimit);
    }

    /// @notice Composite one token into another, mixing visuals and reducing arrow count
    /// @param tokenId The token ID to keep alive (its visual will change)
    /// @param burnId The token ID to composite into the kept token
    function composite(uint256 tokenId, uint256 burnId) external whenNotPaused {
        _composite(tokenId, burnId);
        unchecked {
            ++_arrowsData.burned;
        }
        emit TokensComposited(tokenId, burnId);
    }

    /// @notice Burn a single arrow token without compositing
    /// @param tokenId The token ID to burn
    /// @dev This is a common purpose burn method that does not affect other tokens
    function burn(uint256 tokenId) external whenNotPaused {
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

        // Declare gradient and colorBand outside the conditional block
        uint8 gradient = 0;
        uint8 colorBand = 0;

        // We only need to breed band + gradient up until 4-Arrows.
        if (divisorIndex < 5) {
            // Assign values from _compositeGenes
            (gradient, colorBand) = _compositeGenes(tokenId, burnId);

            toKeep.colorBands[divisorIndex] = colorBand;
            toKeep.gradients[divisorIndex] = gradient;
        }

        // Composite our arrow
        toKeep.composites[divisorIndex] = uint16(burnId);
        toKeep.divisorIndex = nextDivisor;

        // Generate new seed based on parents' seeds and resulting genes
        uint256 newSeed = uint256(
            keccak256(
                abi.encodePacked(
                    _tokenMetadata[tokenId].seed,
                    _tokenMetadata[burnId].seed,
                    gradient, // Use resulting gradient
                    colorBand // Use resulting colorBand
                )
            )
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

    /// @notice Emergency withdrawal of all contract balance
    /// @dev Only callable by the contract owner
    /// @dev Used in case of emergency to recover all funds (ERC20)
    function emergencyWithdraw() external onlyOwner {
        require(address(paymentToken) != address(0), "Payment token not set");
        uint256 balance = paymentToken.balanceOf(address(this));
        require(balance > 0, "No funds to withdraw");

        bool success = paymentToken.transfer(owner(), balance);
        require(success, "ERC20 transfer failed");

        emit EmergencyWithdrawn(balance);
    }

    /// @notice Get the current available prize pool balance (ERC20)
    /// @return The current contract balance of the payment token
    function getAvailablePrizePool() public view returns (uint256) {
        if (address(paymentToken) == address(0)) {
            return 0;
        }
        return paymentToken.balanceOf(address(this));
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
        // Get the winning color string using the index
        string memory winningColor = EightyColors.colors()[winningColorIndex];
        // Compare the hash of the token's first color with the hash of the winning color string
        return keccak256(abi.encodePacked(tokenColors[0])) == keccak256(abi.encodePacked(winningColor));
    }

    /**
     * @notice Get the current winning color string
     * @return The hex string of the current winning color
     */
    function getCurrentWinningColor() public view returns (string memory) {
        return EightyColors.colors()[winningColorIndex];
    }

    /**
     * @notice Get the color string for a given index.
     * @param _index The index (0-79) of the color to retrieve.
     * @return The hex string of the color at the specified index.
     */
    function getColorFromIndex(uint8 _index) public pure returns (string memory) {
        // Calls the function in the library
        return EightyColors.getColorByIndex(_index);
    }

    /**
     * @notice Get the index for a given color string.
     * @param _color The hex string of the color to find (must be one of the 80 colors).
     * @return The index (0-79) of the color.
     * @dev Reverts if the color is not found in the list.
     */
    function getIndexFromColor(string memory _color) public pure returns (uint8) {
        // Calls the function in the library
        return EightyColors.getIndexByColor(_color);
    }

    /// @notice Update the winning color index
    /// @param newIndex The new index (0-79) for the winning color
    function updateWinningColorIndex(uint8 newIndex) external onlyOwner {
        require(newIndex < 80, "Index must be < 80");
        winningColorIndex = newIndex;
        emit WinningColorIndexUpdated(newIndex);
    }

    /// @notice Set the winning color by providing a hex color code
    /// @param colorHex The hex string of the color (e.g., "FFA000")
    /// @dev The color must be one of the 80 predefined colors in EightyColors
    function setWinningColor(string memory colorHex) external onlyOwner {
        uint8 colorIndex = EightyColors.getIndexByColor(colorHex);
        winningColorIndex = colorIndex;
        emit WinningColorSet(colorHex, colorIndex);
        emit WinningColorIndexUpdated(colorIndex);
    }

    /// @notice Claim a prize for a winning token
    /// @param tokenId The winning token ID to burn and claim prize for
    /// @dev The token must be a winning token (have exactly 1 arrow and the winning color)
    function claimPrize(uint256 tokenId) external whenNotPaused {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not token owner");
        require(isWinningToken(tokenId), "Not a winning token");
        require(address(paymentToken) != address(0), "Payment token not set");
        require(prizePool.totalDeposited > 0, "Prize pool empty");
        require(prizePool.actualAvailable > 0, "Actual prize pool is empty");

        // Calculate prize amount (winnerClaimPercentage% of the total deposited)
        uint256 claimAmount = (prizePool.totalDeposited * winnerClaimPercentage) / 100;

        // Ensure claim amount doesn't exceed actual available funds
        if (claimAmount > prizePool.actualAvailable) {
            claimAmount = prizePool.actualAvailable;
        }

        // Ensure we have enough balance
        uint256 contractBalance = paymentToken.balanceOf(address(this));
        require(contractBalance >= claimAmount, "Insufficient funds in contract");

        // Update prize pool state
        prizePool.lastWinnerClaim = uint32(block.timestamp);
        prizePool.totalDeposited -= claimAmount;
        prizePool.actualAvailable -= claimAmount;

        // Burn the token first (to prevent reentrancy)
        _burn(tokenId);
        unchecked {
            ++_arrowsData.burned;
        }

        // Transfer the prize to the winner
        bool success = paymentToken.transfer(msg.sender, claimAmount);
        require(success, "ERC20 transfer failed");

        // Randomly select a new winning color
        uint8 oldColorIndex = winningColorIndex;
        uint8 newColorIndex;

        // Generate random index and make sure it's different from the current one
        do {
            // Use keccak256 to generate pseudorandom number
            uint256 randomSeed = uint256(
                keccak256(
                    abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, tokenId, prizePool.lastWinnerClaim)
                )
            );
            newColorIndex = uint8(randomSeed % 80); // There are 80 colors in EightyColors
        } while (newColorIndex == oldColorIndex);

        // Update the winning color index
        winningColorIndex = newColorIndex;

        // Emit events
        emit PrizeClaimed(tokenId, msg.sender, claimAmount);
        emit TokenBurned(tokenId, msg.sender);
        emit PrizePoolUpdated(prizePool.totalDeposited);
        emit WinningColorIndexUpdated(newColorIndex);
        emit WinningColorSet(EightyColors.getColorByIndex(newColorIndex), newColorIndex);
    }
}
