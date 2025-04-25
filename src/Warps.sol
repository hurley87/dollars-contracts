// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IWarps.sol";
import "./libraries/WarpsArt.sol";
import "./libraries/WarpsMetadata.sol";
import "./libraries/WarpColors.sol";
import "./libraries/Utilities.sol";
import "./standards/WARPS721.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/security/Pausable.sol";

/**
 * @title  Warps
 * @author Hurls
 * @notice Up and to the right.
 */
contract Warps is IWarps, WARPS721, Ownable, Pausable {
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
    Warps _warpsData;

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

    // Add on-chain palette storage per token
    struct Palette {
        uint8 len; // 3 → 2 → 1
        uint24[3] colors; // unused slots stay 0
    }

    mapping(uint256 => Palette) private _palette;

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

    /// @dev Initializes the Warps contract and links the Edition contract.
    constructor() Ownable() {
        _warpsData.minted = 0;
        _warpsData.burned = 0;
        prizePool.lastWinnerClaim = 0;
        prizePool.actualAvailable = 0;
        winningColorIndex = 4; // Set to a valid index (2BDE73 - Kickstarter Green, index 4)
        ownerMintSharePercentage = 40;
        winnerClaimPercentage = 5;
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

        // Check if user has approved the contract to spend their tokens
        uint256 allowance = paymentToken.allowance(msg.sender, address(this));
        require(allowance >= amount, "Check allowance");

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
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, tokenId, msg.sender, _warpsData.minted))
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
        _warpsData.all[tokenId].colorBands[0] = colorBand;
        _warpsData.all[tokenId].gradients[0] = gradient;
    }

    /// @notice Mint new Warps tokens using the specified ERC20 payment token
    /// @param recipient The address to receive the tokens
    function mint(address recipient) external whenNotPaused {
        require(address(paymentToken) != address(0), "Payment token not set");
        require(recipient != address(0), "Invalid recipient");

        uint256 requiredAmount = mintPrice;
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

            StoredWarp storage warp = _warpsData.all[id];
            warp.seed = uint16(id);
            warp.divisorIndex = 0;

            _generateTokenRandomness(id);

            _safeMint(recipient, id);
            _initPalette(id, recipient);

            unchecked {
                ++i;
            }
        }

        unchecked {
            _warpsData.minted += uint32(mintLimit);
        }

        emit TokensMinted(recipient, startTokenId, mintLimit);
    }

    /// @notice Mint new Warps tokens with a free mint if available
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

            StoredWarp storage warp = _warpsData.all[id];
            warp.seed = uint16(id);
            warp.divisorIndex = 0;

            _generateTokenRandomness(id);

            _safeMint(recipient, id);
            _initPalette(id, recipient);

            unchecked {
                ++i;
            }
        }

        unchecked {
            _warpsData.minted += uint32(mintLimit);
        }

        emit TokensMinted(recipient, startTokenId, mintLimit);
    }

    /// @notice Composite one token into another, mixing visuals and reducing warp count
    /// @param tokenId The token ID to keep alive (its visual will change)
    /// @param burnId The token ID to composite into the kept token
    function composite(uint256 tokenId, uint256 burnId) external whenNotPaused {
        _composite(tokenId, burnId);
        unchecked {
            ++_warpsData.burned;
        }
        emit TokensComposited(tokenId, burnId);
    }

    /// @notice Burn a single warp token without compositing
    /// @param tokenId The token ID to burn
    /// @dev This is a common purpose burn method that does not affect other tokens
    function burn(uint256 tokenId) external whenNotPaused {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert NotAllowed();
        }

        _burn(tokenId);
        unchecked {
            ++_warpsData.burned;
        }
        emit TokenBurned(tokenId, msg.sender);
    }

    /// @notice Get the metadata URI for a token
    /// @param tokenId The token ID to get metadata for
    /// @return The metadata URI string
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        // Build warp object
        IWarps.Warp memory warp = WarpsArt.getWarp(tokenId, _warpsData);

        // Load palette
        Palette storage palStore = _palette[tokenId];
        uint24[] memory pal = new uint24[](palStore.len);
        for (uint8 i; i < palStore.len; ++i) {
            pal[i] = palStore.colors[i];
        }

        // Generate SVG based on palette (fallback to default if none)
        bytes memory staticSvg = pal.length > 0
            ? WarpsArt.generateSVGWithPalette(warp, _warpsData, pal)
            : WarpsArt.generateSVG(warp, _warpsData);

        // Prepare JSON metadata
        bytes memory metadata = abi.encodePacked(
            "{",
            '"name": "Warps ',
            Utilities.uint2str(tokenId),
            '",',
            '"description": "Up and to the right.",',
            '"image": ',
            '"data:image/svg+xml;base64,',
            Base64.encode(staticSvg),
            '",',
            '"attributes": [',
            WarpsMetadata.attributes(warp),
            "]",
            "}"
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(metadata)));
    }

    /// @dev Get warp with the stored seed instead of epoch-based randomness
    function _getWarpWithSeed(uint256 tokenId) internal view returns (IWarps.Warp memory) {
        IWarps.Warp memory warp = WarpsArt.getWarp(tokenId, _warpsData);

        // Override the seed with our stored seed
        if (_tokenMetadata[tokenId].seed != 0) {
            warp.seed = _tokenMetadata[tokenId].seed;
        }

        return warp;
    }

    /// @dev Composite one token into to another and burn it.
    /// @param tokenId The token ID to keep. Its art and warp-count will change.
    /// @param burnId The token ID to burn in the process.
    function _composite(uint256 tokenId, uint256 burnId) internal {
        (StoredWarp storage toKeep,, uint8 divisorIndex) = _tokenOperation(tokenId, burnId);

        uint8 nextDivisor = divisorIndex + 1;

        // Declare gradient and colorBand outside the conditional block
        uint8 gradient = 0;
        uint8 colorBand = 0;

        // We only need to breed band + gradient up until 4-Warps.
        if (divisorIndex < 5) {
            // Assign values from _compositeGenes
            (gradient, colorBand) = _compositeGenes(tokenId, burnId);

            toKeep.colorBands[divisorIndex] = colorBand;
            toKeep.gradients[divisorIndex] = gradient;
        }

        // Update on-chain palette before finalizing composite
        _updatePaletteOnComposite(tokenId, burnId, divisorIndex);

        // Composite our warp
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
        emit Composite(tokenId, burnId, WarpsArt.divisors()[toKeep.divisorIndex]);
        emit MetadataUpdate(tokenId);
    }

    /// @dev Composite the gradient and colorBand settings.
    /// @param tokenId The token ID to keep.
    /// @param burnId The token ID to burn.
    function _compositeGenes(uint256 tokenId, uint256 burnId) internal view returns (uint8 gradient, uint8 colorBand) {
        Warp memory keeper = _getWarpWithSeed(tokenId);
        Warp memory burner = _getWarpWithSeed(burnId);

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
        returns (StoredWarp storage toKeep, StoredWarp storage toBurn, uint8 divisorIndex)
    {
        toKeep = _warpsData.all[tokenId];
        toBurn = _warpsData.all[burnId];
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

        // Reset both accounting values since all funds are withdrawn
        prizePool.totalDeposited = 0;
        prizePool.actualAvailable = 0;

        emit EmergencyWithdrawn(balance);
        emit PrizePoolUpdated(0);
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
    /// @dev A token is considered a winner if it has exactly 1 warp and its first palette colour matches
    ///      the current `winningColorIndex` from `WarpColors`.
    function isWinningToken(uint256 tokenId) public view returns (bool) {
        // Ensure token exists
        if (!_exists(tokenId)) return false;

        // Winning rule still requires a single–warp token
        Warp memory warp = _getWarpWithSeed(tokenId);
        if (warp.warpsCount != 1) return false;

        // Fetch palette and ensure it is initialised
        Palette storage p = _palette[tokenId];
        if (p.len == 0) return false;

        // Compare first palette colour with the canonical winning colour code
        return p.colors[0] == _warpColorCode(winningColorIndex);
    }

    /**
     * @notice Get the current winning color string
     * @return The hex string of the current winning color
     */
    function getCurrentWinningColor() public view returns (string memory) {
        return WarpColors.colors()[winningColorIndex];
    }

    /**
     * @notice Get the color string for a given index.
     * @param _index The index (0-6) of the color to retrieve.
     * @return The hex string of the color at the specified index.
     */
    function getColorFromIndex(uint8 _index) public pure returns (string memory) {
        // Calls the function in the library
        return WarpColors.getColorByIndex(_index);
    }

    /**
     * @notice Get the index for a given color string.
     * @param _color The hex string of the color to find (must be one of the 7 colors).
     * @return The index (0-6) of the color.
     * @dev Reverts if the color is not found in the list.
     */
    function getIndexFromColor(string memory _color) public pure returns (uint8) {
        // Calls the function in the library
        return WarpColors.getIndexByColor(_color);
    }

    /// @notice Update the winning color index
    /// @param newIndex The new index (0-6) for the winning color
    function updateWinningColorIndex(uint8 newIndex) external onlyOwner {
        require(newIndex < 7, "Index must be < 7");
        winningColorIndex = newIndex;
        emit WinningColorIndexUpdated(newIndex);
    }

    /// @notice Set the winning color by providing a hex color code
    /// @param colorHex The hex string of the color (e.g., "FFA000")
    /// @dev The color must be one of the 7 predefined colors in WarpColors
    function setWinningColor(string memory colorHex) external onlyOwner {
        uint8 colorIndex = WarpColors.getIndexByColor(colorHex);
        winningColorIndex = colorIndex;
        emit WinningColorSet(colorHex, colorIndex);
        emit WinningColorIndexUpdated(colorIndex);
    }

    /// @notice Claim a prize for a winning token
    /// @param tokenId The winning token ID to burn and claim prize for
    /// @dev The token must be a winning token (have exactly 1 warp and the winning color)
    function claimPrize(uint256 tokenId) external whenNotPaused {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not token owner");
        require(isWinningToken(tokenId), "Not a winning token");
        require(address(paymentToken) != address(0), "Payment token not set");
        require(prizePool.totalDeposited > 0, "Prize pool empty");
        require(prizePool.actualAvailable > 0, "Actual prize pool is empty");

        // Check actual contract balance first to ensure we have tokens
        uint256 contractBalance = paymentToken.balanceOf(address(this));
        require(contractBalance > 0, "No tokens in contract");

        // Calculate prize amount (winnerClaimPercentage% of the total deposited)
        uint256 claimAmount = (prizePool.totalDeposited * winnerClaimPercentage) / 100;

        // Ensure claim amount doesn't exceed actual available funds
        if (claimAmount > prizePool.actualAvailable) {
            claimAmount = prizePool.actualAvailable;
        }

        // Ensure we have enough balance for the specific claim amount
        require(contractBalance >= claimAmount, "Insufficient tokens for prize claim");

        // Update prize pool state
        prizePool.lastWinnerClaim = uint32(block.timestamp);
        prizePool.totalDeposited -= claimAmount;
        prizePool.actualAvailable -= claimAmount;

        // Burn the token first (to prevent reentrancy)
        _burn(tokenId);
        unchecked {
            ++_warpsData.burned;
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
            newColorIndex = uint8(randomSeed % 7); // There are 7 colors in WarpColors
        } while (newColorIndex == oldColorIndex);

        // Update the winning color index
        winningColorIndex = newColorIndex;

        // Emit events
        emit PrizeClaimed(tokenId, msg.sender, claimAmount);
        emit TokenBurned(tokenId, msg.sender);
        emit PrizePoolUpdated(prizePool.totalDeposited);
        emit WinningColorIndexUpdated(newColorIndex);
        emit WinningColorSet(WarpColors.getColorByIndex(newColorIndex), newColorIndex);
    }

    // ====================== Palette Logic ======================

    /// @dev Initialize a palette of 3 random colors for a newly minted token.
    ///      Uses packed uint24 RGB values for gas efficiency.
    function _initPalette(uint256 tokenId, address minter) internal {
        Palette storage p = _palette[tokenId];
        if (p.len != 0) return; // already initialised
        p.len = 3;

        uint256 s = uint256(keccak256(abi.encodePacked(block.prevrandao, tokenId, minter)));
        // Map random bytes to WarpColors indices (0-6) and then to uint24 values
        p.colors[0] = _warpColorCode(uint8(s & 0xFF) % 7);
        p.colors[1] = _warpColorCode(uint8((s >> 8) & 0xFF) % 7);
        p.colors[2] = _warpColorCode(uint8((s >> 16) & 0xFF) % 7);
    }

    /// @dev Return the uint24 RGB code for the 7 canonical WarpColors.
    function _warpColorCode(uint8 index) internal pure returns (uint24) {
        if (index == 0) return 0xFF007A; // Uniswap Pink
        if (index == 1) return 0x855DCD; // Farcaster Purple
        if (index == 2) return 0xFF9900; // Bitcoin Orange
        if (index == 3) return 0xFFCC00; // IKEA Yellow
        if (index == 4) return 0x2BDE73; // Kickstarter Green
        if (index == 5) return 0x00FFFF; // Cyan
        if (index == 6) return 0xFFFFFF; // White
        revert("Index out of bounds");
    }

    /// @dev Update the palette when compositing two tokens.
    ///      Shrinks from 3 → 2 → 1 colours across the first two composites.
    function _updatePaletteOnComposite(uint256 keepId, uint256 burnId, uint8 divisorIdx) internal {
        Palette storage a = _palette[keepId];
        Palette storage b = _palette[burnId];
        uint256 r = uint256(keccak256(abi.encodePacked(a.colors[0], b.colors[0], block.prevrandao)));

        if (divisorIdx == 0 && a.len == 3 && b.len == 3) {
            // First composite → 2 colours (one from each parent)
            a.colors[0] = a.colors[uint8(r) % 3];
            a.colors[1] = b.colors[uint8(r >> 8) % 3];
            a.colors[2] = 0;
            a.len = 2;
        } else if (divisorIdx == 1 && a.len == 2 && b.len == 2) {
            // Second composite → 1 colour (picked from either parent)
            a.colors[0] = (r & 1) == 0 ? a.colors[uint8(r) % 2] : b.colors[uint8(r >> 8) % 2];
            a.colors[1] = 0;
            a.len = 1;
        }
    }

    /// @notice Return this token's current palette as a dynamic array.
    function tokenColors(uint256 id) external view returns (uint24[] memory) {
        Palette storage p = _palette[id];
        uint24[] memory out = new uint24[](p.len);
        for (uint8 i; i < p.len; ++i) {
            out[i] = p.colors[i];
        }
        return out;
    }
}
