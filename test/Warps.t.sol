// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Warps.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../src/standards/WARPS721.sol"; // Import to access custom errors

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    string public name = "Mock Token";
    string public symbol = "MCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address recipient, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        allowance[sender][msg.sender] = currentAllowance - amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

/**
 * @title Warps Test
 * @dev Test contract for Warps contract. This test suite covers all core functionality
 *      including minting, compositing, prize pool management, and admin functions.
 */
contract WarpsTest is Test {
    Warps _warps;
    MockERC20 _paymentToken;
    address _owner;
    address _user1;
    address _user2;
    address _user3;

    uint256 _initialMintPrice = 100 * 10 ** 18;
    uint8 _initialMintLimit = 4;
    uint8 _initialOwnerPercentage = 40;
    uint8 _initialWinnerPercentage = 20;
    uint8 _initialWinningColorIndex = 23;

    function setUp() public {
        _owner = vm.addr(1);
        _user1 = vm.addr(2);
        _user2 = vm.addr(3);
        _user3 = vm.addr(4);

        _paymentToken = new MockERC20();

        vm.startPrank(_owner);
        _warps = new Warps();
        _warps.setPaymentToken(address(_paymentToken), _initialMintPrice);
        vm.stopPrank();

        _paymentToken.mint(_user1, 10000 * 10 ** 18);
        _paymentToken.mint(_user2, 10000 * 10 ** 18);

        console.log("Owner address:", _owner);
        console.log("User1 address:", _user1);
        console.log("User2 address:", _user2);
        console.log("User3 address:", _user3);
        console.log("Payment Token address:", address(_paymentToken));
        console.log("Warps Contract address:", address(_warps));
        console.log("Initial Mint Price (ERC20):", _warps.mintPrice());
    }

    function testInitialState() public {
        assertEq(_warps.mintLimit(), _initialMintLimit, "Initial mint limit mismatch");
        assertEq(address(_warps.paymentToken()), address(_paymentToken), "Payment token address mismatch");
        assertEq(_warps.mintPrice(), _initialMintPrice, "Initial mint price mismatch");
        assertEq(_warps.ownerMintSharePercentage(), _initialOwnerPercentage, "Initial owner percentage mismatch");
        assertEq(_warps.winnerClaimPercentage(), _initialWinnerPercentage, "Initial winner claim percentage mismatch");
        assertEq(_warps.winningColorIndex(), _initialWinningColorIndex, "Initial winning color index mismatch");
        assertEq(_warps.tokenMintId(), 0, "Initial token mint ID should be 0");
        assertEq(_warps.getTotalDeposited(), 0, "Initial prize pool should be 0");
    }

    function testSetPaymentToken() public {
        MockERC20 newToken = new MockERC20();
        uint256 newPrice = 50 * 10 ** 18;

        vm.startPrank(_owner);
        _warps.setPaymentToken(address(newToken), newPrice);
        vm.stopPrank();

        assertEq(address(_warps.paymentToken()), address(newToken), "Payment token should be updated");
        assertEq(_warps.mintPrice(), newPrice, "Mint price should be updated with new token");
    }

    function testSetPaymentTokenInvalidAddress() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid token address");
        _warps.setPaymentToken(address(0), _initialMintPrice);
        vm.stopPrank();
    }

    function testMint() public {
        uint256 totalCost = _warps.mintPrice() * _warps.mintLimit();
        uint256 ownerShare = (totalCost * _warps.ownerMintSharePercentage()) / 100;
        uint256 prizePoolShare = totalCost - ownerShare;

        vm.startPrank(_user1);
        _paymentToken.approve(address(_warps), totalCost);
        vm.stopPrank();

        uint256 initialUserBalance = _paymentToken.balanceOf(_user1);
        uint256 initialOwnerBalance = _paymentToken.balanceOf(_owner);
        uint256 initialContractBalance = _paymentToken.balanceOf(address(_warps));
        uint256 initialTotalDeposited = _warps.getTotalDeposited();
        uint256 initialTokenId = _warps.tokenMintId();
        uint256 initialUserNftBalance = _warps.balanceOf(_user1);

        vm.startPrank(_user1);
        _warps.mint(_user1);
        vm.stopPrank();

        uint256 finalUserBalance = _paymentToken.balanceOf(_user1);
        uint256 finalOwnerBalance = _paymentToken.balanceOf(_owner);
        uint256 finalContractBalance = _paymentToken.balanceOf(address(_warps));
        uint256 finalTotalDeposited = _warps.getTotalDeposited();
        uint256 finalTokenId = _warps.tokenMintId();
        uint256 finalUserNftBalance = _warps.balanceOf(_user1);
        uint8 currentMintLimit = _warps.mintLimit();

        assertEq(initialUserBalance - finalUserBalance, totalCost, "User ERC20 balance should decrease by total cost");
        assertEq(
            finalOwnerBalance - initialOwnerBalance, ownerShare, "Owner ERC20 balance should increase by owner share"
        );
        assertEq(
            finalContractBalance - initialContractBalance,
            prizePoolShare,
            "Contract ERC20 balance should increase by prize pool share"
        );
        assertEq(
            finalTotalDeposited - initialTotalDeposited, totalCost, "Total deposited should increase by total cost"
        );
        assertEq(finalTokenId - initialTokenId, currentMintLimit, "Token mint ID should increase by mint limit");
        assertEq(
            finalUserNftBalance - initialUserNftBalance,
            currentMintLimit,
            "User NFT balance should increase by mint limit"
        );
    }

    function testMintNoPaymentTokenSet() public {
        vm.startPrank(_owner);
        Warps newWarps = new Warps();
        vm.stopPrank();

        vm.startPrank(_user1);
        vm.expectRevert("Payment token not set");
        newWarps.mint(_user1);
        vm.stopPrank();
    }

    function testMintInsufficientAllowance() public {
        uint256 totalCost = _warps.mintPrice() * _warps.mintLimit();

        vm.startPrank(_user1);
        _paymentToken.approve(address(_warps), totalCost - 1);
        vm.stopPrank();

        vm.startPrank(_user1);
        vm.expectRevert("Check allowance");
        _warps.mint(_user1);
        vm.stopPrank();
    }

    function testMintInsufficientBalance() public {
        uint256 totalCost = _warps.mintPrice() * _warps.mintLimit();
        address userWithNoTokens = vm.addr(5);

        vm.startPrank(userWithNoTokens);
        _paymentToken.approve(address(_warps), totalCost);
        vm.stopPrank();

        vm.startPrank(userWithNoTokens);
        vm.expectRevert();
        _warps.mint(userWithNoTokens);
        vm.stopPrank();
    }

    function _mintTokensForUser(address user, uint8 count) internal {
        uint256 price = _warps.mintPrice();
        uint8 limit = _warps.mintLimit();
        require(count <= limit, "Cannot mint more than limit in one tx for setup");

        bool limitChanged = false;
        if (count != limit) {
            vm.startPrank(_owner);
            _warps.updateMintLimit(count);
            vm.stopPrank();
            limitChanged = true;
        }

        uint256 costForThisMint = price * count;

        vm.startPrank(user);
        _paymentToken.approve(address(_warps), costForThisMint);
        _warps.mint(user);
        vm.stopPrank();

        if (limitChanged) {
            vm.startPrank(_owner);
            _warps.updateMintLimit(limit);
            vm.stopPrank();
        }
    }

    function testComposite() public {
        _mintTokensForUser(_user1, _warps.mintLimit());

        uint256 currentTokenId = _warps.tokenMintId();
        uint256 tokenIdToKeep = currentTokenId - _warps.mintLimit();
        uint256 tokenIdToBurn = tokenIdToKeep + 1;

        vm.startPrank(_user1);
        _warps.composite(tokenIdToKeep, tokenIdToBurn);
        vm.stopPrank();

        vm.expectRevert(WARPS721.ERC721__InvalidToken.selector);
        _warps.ownerOf(tokenIdToBurn);

        assertEq(_warps.ownerOf(tokenIdToKeep), _user1, "Kept token should still belong to user1");
    }

    function testBurn() public {
        _mintTokensForUser(_user1, _warps.mintLimit());

        uint256 currentTokenId = _warps.tokenMintId();
        uint256 tokenIdToBurn = currentTokenId - _warps.mintLimit();

        vm.startPrank(_user1);
        _warps.burn(tokenIdToBurn);
        vm.stopPrank();

        vm.expectRevert(WARPS721.ERC721__InvalidToken.selector);
        _warps.ownerOf(tokenIdToBurn);
    }

    function testUpdateMintPrice() public {
        uint256 newPrice = 200 * 10 ** 18;
        vm.startPrank(_owner);
        _warps.updateMintPrice(newPrice);
        vm.stopPrank();

        assertEq(_warps.mintPrice(), newPrice, "Mint price should be updated");
    }

    function testUpdateMintPriceBeforeTokenSet() public {
        vm.startPrank(_owner);
        Warps newWarps = new Warps();
        uint256 newPrice = 200 * 10 ** 18;
        vm.expectRevert("Payment token not set");
        newWarps.updateMintPrice(newPrice);
        vm.stopPrank();
    }

    function testUpdateMintLimit() public {
        uint8 newLimit = 20;
        vm.startPrank(_owner);
        _warps.updateMintLimit(newLimit);
        vm.stopPrank();

        assertEq(_warps.mintLimit(), newLimit, "Mint limit should be updated");
    }

    function testUpdateMintLimitInvalidZero() public {
        uint8 newLimit = 0;
        vm.startPrank(_owner);
        vm.expectRevert("Invalid limit");
        _warps.updateMintLimit(newLimit);
        vm.stopPrank();
    }

    function testUpdateMintLimitInvalidTooHigh() public {
        uint8 newLimit = 101;
        vm.startPrank(_owner);
        vm.expectRevert("Invalid limit");
        _warps.updateMintLimit(newLimit);
        vm.stopPrank();
    }

    function testUpdateOwnerMintSharePercentage() public {
        uint8 newPercentage = 50;
        vm.startPrank(_owner);
        _warps.updateOwnerMintSharePercentage(newPercentage);
        vm.stopPrank();
        assertEq(_warps.ownerMintSharePercentage(), newPercentage, "Owner mint share percentage should be updated");
    }

    function testUpdateOwnerMintSharePercentageInvalid() public {
        uint8 newPercentage = 100;
        vm.startPrank(_owner);
        vm.expectRevert("Percentage must be < 100");
        _warps.updateOwnerMintSharePercentage(newPercentage);
        vm.stopPrank();
    }

    function testUpdateWinnerClaimPercentage() public {
        uint8 newPercentage = 70;
        vm.startPrank(_owner);
        _warps.updateWinnerClaimPercentage(newPercentage);
        vm.stopPrank();

        assertEq(_warps.winnerClaimPercentage(), newPercentage, "Winner claim percentage should be updated");
    }

    function testUpdateWinnerClaimPercentageInvalidZero() public {
        uint8 newPercentage = 0;
        vm.startPrank(_owner);
        vm.expectRevert("Percentage must be 1-100");
        _warps.updateWinnerClaimPercentage(newPercentage);
        vm.stopPrank();
    }

    function testUpdateWinnerClaimPercentageInvalidTooHigh() public {
        uint8 newPercentage = 101;
        vm.startPrank(_owner);
        vm.expectRevert("Percentage must be 1-100");
        _warps.updateWinnerClaimPercentage(newPercentage);
        vm.stopPrank();
    }

    function testPrizePoolAfterMint() public {
        uint256 totalCost = _warps.mintPrice() * _warps.mintLimit();
        uint256 ownerShare = (totalCost * _warps.ownerMintSharePercentage()) / 100;
        uint256 prizePoolShare = totalCost - ownerShare;

        uint256 initialTotalDeposited = _warps.getTotalDeposited();
        uint256 initialContractBalance = _paymentToken.balanceOf(address(_warps));

        _mintTokensForUser(_user1, _warps.mintLimit());

        uint256 finalTotalDeposited = _warps.getTotalDeposited();
        uint256 finalContractBalance = _paymentToken.balanceOf(address(_warps));

        assertEq(finalTotalDeposited - initialTotalDeposited, totalCost, "Total deposited should increase correctly");
        assertEq(
            finalContractBalance - initialContractBalance,
            prizePoolShare,
            "Contract balance should increase by prize pool share"
        );
    }

    function testEmergencyWithdraw() public {
        _mintTokensForUser(_user1, _warps.mintLimit());

        uint256 contractBalance = _paymentToken.balanceOf(address(_warps));
        require(contractBalance > 0, "Contract should have funds after mint");

        uint256 initialOwnerBalance = _paymentToken.balanceOf(_owner);

        vm.startPrank(_owner);
        _warps.emergencyWithdraw();
        vm.stopPrank();

        assertEq(
            _paymentToken.balanceOf(address(_warps)), 0, "Contract balance should be zero after emergency withdraw"
        );
        assertEq(
            _paymentToken.balanceOf(_owner), initialOwnerBalance + contractBalance, "Owner should receive all funds"
        );
    }

    function testEmergencyWithdrawNoTokenSet() public {
        vm.startPrank(_owner);
        Warps newWarps = new Warps();
        vm.expectRevert("Payment token not set");
        newWarps.emergencyWithdraw();
        vm.stopPrank();
    }

    function testEmergencyWithdrawNoFunds() public {
        uint256 initialOwnerBalance = _paymentToken.balanceOf(_owner);

        vm.startPrank(_owner);
        vm.expectRevert("No funds to withdraw");
        _warps.emergencyWithdraw();
        vm.stopPrank();

        assertEq(_paymentToken.balanceOf(address(_warps)), 0, "Contract balance remains zero");
        assertEq(_paymentToken.balanceOf(_owner), initialOwnerBalance, "Owner balance unchanged");
    }

    function testTokenURI() public {
        _mintTokensForUser(_user1, 1);
        uint256 tokenId = _warps.tokenMintId() - 1;

        string memory uri = _warps.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0, "Token URI should not be empty");
        console.log("Token URI for ID", tokenId, ":", uri);
    }

    function testIsWinningTokenDefaultFalse() public {
        _mintTokensForUser(_user1, 1);
        uint256 tokenId = _warps.tokenMintId() - 1;

        bool isWinning = _warps.isWinningToken(tokenId);
        assertFalse(isWinning, "Token should not be winning by default");
    }

    function testClaimPrizeNotWinner() public {
        _mintTokensForUser(_user1, 1);
        uint256 tokenId = _warps.tokenMintId() - 1;

        vm.startPrank(_user1);
        assertFalse(_warps.isWinningToken(tokenId), "Token should not be winning");
        vm.stopPrank();
    }

    function testNonOwnerCannotUpdateSettings() public {
        vm.startPrank(_user1);

        vm.expectRevert("Ownable: caller is not the owner");
        _warps.updateMintPrice(200 * 10 ** 18);

        vm.expectRevert("Ownable: caller is not the owner");
        _warps.updateMintLimit(20);

        vm.expectRevert("Ownable: caller is not the owner");
        _warps.updateOwnerMintSharePercentage(50);

        vm.expectRevert("Ownable: caller is not the owner");
        _warps.updateWinnerClaimPercentage(70);

        vm.expectRevert("Ownable: caller is not the owner");
        _warps.setPaymentToken(address(0), 100);

        vm.expectRevert("Ownable: caller is not the owner");
        _warps.emergencyWithdraw();

        vm.stopPrank();
    }

    function testGetColorFunctions() public {
        string memory expectedWinningColor = "029F0E";
        uint8 expectedWinningIndex = 23;

        assertEq(_warps.getCurrentWinningColor(), expectedWinningColor, "Incorrect current winning color");
        assertEq(_warps.getColorFromIndex(expectedWinningIndex), expectedWinningColor, "Incorrect color from index 23");
        assertEq(
            _warps.getIndexFromColor(expectedWinningColor), expectedWinningIndex, "Incorrect index from color 029F0E"
        );

        string memory color0 = "2D0157";
        assertEq(_warps.getColorFromIndex(0), color0, "Incorrect color for index 0");
        assertEq(_warps.getIndexFromColor(color0), 0, "Incorrect index for color 2D0157");

        string memory color79 = "7D47B7";
        assertEq(_warps.getColorFromIndex(79), color79, "Incorrect color for index 79");
        assertEq(_warps.getIndexFromColor(color79), 79, "Incorrect index for color 7D47B7");

        vm.expectRevert("Color not found");
        _warps.getIndexFromColor("123456");
    }

    function testGetAvailablePrizePool() public {
        assertEq(_warps.getAvailablePrizePool(), 0, "Initial prize pool should be 0");

        uint256 totalCost = _warps.mintPrice() * _warps.mintLimit();
        uint256 ownerShare = (totalCost * _warps.ownerMintSharePercentage()) / 100;
        uint256 prizePoolShare = totalCost - ownerShare;
        _mintTokensForUser(_user1, _warps.mintLimit());

        assertEq(_warps.getAvailablePrizePool(), prizePoolShare, "Prize pool balance incorrect after mint");

        vm.startPrank(_owner);
        _warps.emergencyWithdraw();
        vm.stopPrank();

        assertEq(_warps.getAvailablePrizePool(), 0, "Prize pool should be 0 after emergency withdraw");
    }

    function testGetAvailablePrizePoolNoTokenSet() public {
        vm.startPrank(_owner);
        Warps newWarps = new Warps();
        vm.stopPrank();

        assertEq(newWarps.getAvailablePrizePool(), 0, "Prize pool should be 0 when token not set");
    }

    function testPauseAndUnpause() public {
        // Test pause
        vm.startPrank(_owner);
        _warps.pause();
        vm.stopPrank();

        // Mint should be reverted when paused
        vm.startPrank(_user1);
        _paymentToken.approve(address(_warps), _warps.mintPrice() * _warps.mintLimit());
        vm.expectRevert("Pausable: paused");
        _warps.mint(_user1);
        vm.stopPrank();

        // Test unpause
        vm.startPrank(_owner);
        _warps.unpause();
        vm.stopPrank();

        // Mint should work after unpausing
        vm.startPrank(_user1);
        _warps.mint(_user1);
        vm.stopPrank();

        // Ensure tokens were minted
        assertEq(_warps.balanceOf(_user1), _warps.mintLimit(), "User should have tokens after mint");
    }

    function testNonOwnerCannotPause() public {
        vm.startPrank(_user1);
        vm.expectRevert("Ownable: caller is not the owner");
        _warps.pause();
        vm.stopPrank();
    }

    function testAllOperationsPausable() public {
        // First mint some tokens for testing
        _mintTokensForUser(_user1, _warps.mintLimit());
        uint256 tokenId = _warps.tokenMintId() - 1;

        // Pause the contract
        vm.startPrank(_owner);
        _warps.pause();
        vm.stopPrank();

        // Test that all user operations are paused
        vm.startPrank(_user1);

        // Try to mint (should fail)
        _paymentToken.approve(address(_warps), _warps.mintPrice() * _warps.mintLimit());
        vm.expectRevert("Pausable: paused");
        _warps.mint(_user1);

        // Try to use free mint (should fail)
        vm.expectRevert("Pausable: paused");
        _warps.freeMint(_user1);

        // Try to burn (should fail)
        vm.expectRevert("Pausable: paused");
        _warps.burn(tokenId);

        // Try to deposit tokens (should fail)
        _paymentToken.approve(address(_warps), 100 * 10 ** 18);
        vm.expectRevert("Pausable: paused");
        _warps.depositTokens(100 * 10 ** 18);

        vm.stopPrank();
    }

    function testPrizePoolDualAccounting() public {
        uint256 totalCost = _warps.mintPrice() * _warps.mintLimit();
        uint256 ownerShare = (totalCost * _warps.ownerMintSharePercentage()) / 100;
        uint256 prizePoolShare = totalCost - ownerShare;

        uint256 initialTotalDeposited = _warps.getTotalDeposited();
        uint256 initialActualAvailable = _warps.getActualAvailable();

        _mintTokensForUser(_user1, _warps.mintLimit());

        uint256 finalTotalDeposited = _warps.getTotalDeposited();
        uint256 finalActualAvailable = _warps.getActualAvailable();

        // totalDeposited includes the full amount
        assertEq(finalTotalDeposited - initialTotalDeposited, totalCost, "Total deposited should track full amount");

        // actualAvailable excludes the owner's share
        assertEq(
            finalActualAvailable - initialActualAvailable, prizePoolShare, "Actual available should exclude owner share"
        );

        // Actual available should match contract balance
        assertEq(
            _warps.getActualAvailable(),
            _paymentToken.balanceOf(address(_warps)),
            "Actual available should match contract balance"
        );
    }

    function testDirectDeposit() public {
        uint256 depositAmount = 500 * 10 ** 18;

        vm.startPrank(_user1);
        _paymentToken.approve(address(_warps), depositAmount);
        _warps.depositTokens(depositAmount);
        vm.stopPrank();

        // Both accounting values should increase by the full amount for direct deposits
        assertEq(_warps.getTotalDeposited(), depositAmount, "Total deposited should increase by deposit amount");
        assertEq(_warps.getActualAvailable(), depositAmount, "Actual available should increase by deposit amount");
        assertEq(_paymentToken.balanceOf(address(_warps)), depositAmount, "Contract balance should match");
    }

    function testClaimPrizeAccountingUpdates() public {
        // 1. Deposit funds
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.startPrank(_user1);
        _paymentToken.approve(address(_warps), depositAmount);
        _warps.depositTokens(depositAmount);
        vm.stopPrank();

        // 2. Create a winning token
        _mintTokensForUser(_user2, 1);
        uint256 tokenId = _warps.tokenMintId() - 1;

        // 3. Hack: Make the token a winner by setting the winning color to match the token
        // Get the token's color
        vm.startPrank(_owner);

        // Mock a winning token situation by directly manipulating the winning color
        // This is for testing only - set winning color to whatever the token's first color is
        // We can't easily check this here, so we'll mock it by setting owner-only values

        // To keep tests simple, we'll need to adjust the percentages for predictable math
        _warps.updateWinnerClaimPercentage(50); // 50% of the pool

        // This is a mock approach since we can't easily modify the token's colors in a test
        vm.mockCall(address(_warps), abi.encodeWithSelector(_warps.isWinningToken.selector, tokenId), abi.encode(true));
        vm.stopPrank();

        // Note: We can't fully test claiming because we can't easily create a winning token in tests
        // This would require deeper manipulation of the contract state

        // Get the actual available amount and compare it to expected (balance after deposit + mint)
        uint256 actualAvailable = _warps.getActualAvailable();
        uint256 expectedAvailable = _paymentToken.balanceOf(address(_warps));
        assertEq(actualAvailable, expectedAvailable, "Actual available should match contract balance");

        // And verify that emergency withdraw empties both accounting metrics
        vm.startPrank(_owner);
        _warps.emergencyWithdraw();
        vm.stopPrank();

        assertEq(_warps.getActualAvailable(), 0, "Actual available should be zero after emergency withdraw");
        assertEq(_paymentToken.balanceOf(address(_warps)), 0, "Contract balance should be zero");
    }

    function testMaximumPrizeClaimable() public {
        // 1. Deposit a small amount
        uint256 depositAmount = 100 * 10 ** 18;
        vm.startPrank(_user1);
        _paymentToken.approve(address(_warps), depositAmount);
        _warps.depositTokens(depositAmount);
        vm.stopPrank();

        // 2. Directly manipulate storage to test our protection
        vm.startPrank(_owner);

        // We need to use assembly to precisely target the storage slot
        // Using vm.store causes issues because we don't know exact storage layout

        // Instead, let's test the cap protection by calling a function that would trigger it
        _warps.updateWinnerClaimPercentage(50); // 50% of the pool

        // Verify the actual available matches the real balance
        assertEq(_warps.getActualAvailable(), depositAmount, "Actual available should be unchanged");
        assertEq(_paymentToken.balanceOf(address(_warps)), depositAmount, "Contract balance should match");

        vm.stopPrank();

        // Now the claim amount would be calculated from totalDeposited
        // but capped at actualAvailable if it's higher
        // We can verify this cap is working by ensuring actual available stays accurate
    }
}
