// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Dollars.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../src/standards/ARROWS721.sol"; // Import to access custom errors

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
 * @title Dollars Test
 * @dev Test contract for Dollars contract. This test suite covers all core functionality
 *      including minting, compositing, prize pool management, and admin functions.
 */
contract DollarsTest is Test {
    Dollars _dollars;
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
        _dollars = new Dollars();
        _dollars.setPaymentToken(address(_paymentToken), _initialMintPrice);
        vm.stopPrank();

        _paymentToken.mint(_user1, 10000 * 10 ** 18);
        _paymentToken.mint(_user2, 10000 * 10 ** 18);

        console.log("Owner address:", _owner);
        console.log("User1 address:", _user1);
        console.log("User2 address:", _user2);
        console.log("User3 address:", _user3);
        console.log("Payment Token address:", address(_paymentToken));
        console.log("Dollars Contract address:", address(_dollars));
        console.log("Initial Mint Price (ERC20):", _dollars.mintPrice());
    }

    function testInitialState() public {
        assertEq(_dollars.mintLimit(), _initialMintLimit, "Initial mint limit mismatch");
        assertEq(address(_dollars.paymentToken()), address(_paymentToken), "Payment token address mismatch");
        assertEq(_dollars.mintPrice(), _initialMintPrice, "Initial mint price mismatch");
        assertEq(_dollars.ownerMintSharePercentage(), _initialOwnerPercentage, "Initial owner percentage mismatch");
        assertEq(_dollars.winnerClaimPercentage(), _initialWinnerPercentage, "Initial winner claim percentage mismatch");
        assertEq(_dollars.winningColorIndex(), _initialWinningColorIndex, "Initial winning color index mismatch");
        assertEq(_dollars.tokenMintId(), 0, "Initial token mint ID should be 0");
        assertEq(_dollars.getTotalDeposited(), 0, "Initial prize pool should be 0");
    }

    function testSetPaymentToken() public {
        MockERC20 newToken = new MockERC20();
        uint256 newPrice = 50 * 10 ** 18;

        vm.startPrank(_owner);
        _dollars.setPaymentToken(address(newToken), newPrice);
        vm.stopPrank();

        assertEq(address(_dollars.paymentToken()), address(newToken), "Payment token should be updated");
        assertEq(_dollars.mintPrice(), newPrice, "Mint price should be updated with new token");
    }

    function testSetPaymentTokenInvalidAddress() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid token address");
        _dollars.setPaymentToken(address(0), _initialMintPrice);
        vm.stopPrank();
    }

    function testMint() public {
        uint256 totalCost = _dollars.mintPrice() * _dollars.mintLimit();
        uint256 ownerShare = (totalCost * _dollars.ownerMintSharePercentage()) / 100;
        uint256 prizePoolShare = totalCost - ownerShare;

        vm.startPrank(_user1);
        _paymentToken.approve(address(_dollars), totalCost);
        vm.stopPrank();

        uint256 initialUserBalance = _paymentToken.balanceOf(_user1);
        uint256 initialOwnerBalance = _paymentToken.balanceOf(_owner);
        uint256 initialContractBalance = _paymentToken.balanceOf(address(_dollars));
        uint256 initialTotalDeposited = _dollars.getTotalDeposited();
        uint256 initialTokenId = _dollars.tokenMintId();
        uint256 initialUserNftBalance = _dollars.balanceOf(_user1);

        vm.startPrank(_user1);
        _dollars.mint(_user1);
        vm.stopPrank();

        uint256 finalUserBalance = _paymentToken.balanceOf(_user1);
        uint256 finalOwnerBalance = _paymentToken.balanceOf(_owner);
        uint256 finalContractBalance = _paymentToken.balanceOf(address(_dollars));
        uint256 finalTotalDeposited = _dollars.getTotalDeposited();
        uint256 finalTokenId = _dollars.tokenMintId();
        uint256 finalUserNftBalance = _dollars.balanceOf(_user1);
        uint8 currentMintLimit = _dollars.mintLimit();

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
        Dollars newDollars = new Dollars();
        vm.stopPrank();

        vm.startPrank(_user1);
        vm.expectRevert("Payment token not set");
        newDollars.mint(_user1);
        vm.stopPrank();
    }

    function testMintInsufficientAllowance() public {
        uint256 totalCost = _dollars.mintPrice() * _dollars.mintLimit();

        vm.startPrank(_user1);
        _paymentToken.approve(address(_dollars), totalCost - 1);
        vm.stopPrank();

        vm.startPrank(_user1);
        vm.expectRevert("Check allowance");
        _dollars.mint(_user1);
        vm.stopPrank();
    }

    function testMintInsufficientBalance() public {
        uint256 totalCost = _dollars.mintPrice() * _dollars.mintLimit();
        address userWithNoTokens = vm.addr(5);

        vm.startPrank(userWithNoTokens);
        _paymentToken.approve(address(_dollars), totalCost);
        vm.stopPrank();

        vm.startPrank(userWithNoTokens);
        vm.expectRevert();
        _dollars.mint(userWithNoTokens);
        vm.stopPrank();
    }

    function _mintTokensForUser(address user, uint8 count) internal {
        uint256 price = _dollars.mintPrice();
        uint8 limit = _dollars.mintLimit();
        require(count <= limit, "Cannot mint more than limit in one tx for setup");

        bool limitChanged = false;
        if (count != limit) {
            vm.startPrank(_owner);
            _dollars.updateMintLimit(count);
            vm.stopPrank();
            limitChanged = true;
        }

        uint256 costForThisMint = price * count;

        vm.startPrank(user);
        _paymentToken.approve(address(_dollars), costForThisMint);
        _dollars.mint(user);
        vm.stopPrank();

        if (limitChanged) {
            vm.startPrank(_owner);
            _dollars.updateMintLimit(limit);
            vm.stopPrank();
        }
    }

    function testComposite() public {
        _mintTokensForUser(_user1, _dollars.mintLimit());

        uint256 currentTokenId = _dollars.tokenMintId();
        uint256 tokenIdToKeep = currentTokenId - _dollars.mintLimit();
        uint256 tokenIdToBurn = tokenIdToKeep + 1;

        vm.startPrank(_user1);
        _dollars.composite(tokenIdToKeep, tokenIdToBurn);
        vm.stopPrank();

        vm.expectRevert(ARROWS721.ERC721__InvalidToken.selector);
        _dollars.ownerOf(tokenIdToBurn);

        assertEq(_dollars.ownerOf(tokenIdToKeep), _user1, "Kept token should still belong to user1");
    }

    function testBurn() public {
        _mintTokensForUser(_user1, _dollars.mintLimit());

        uint256 currentTokenId = _dollars.tokenMintId();
        uint256 tokenIdToBurn = currentTokenId - _dollars.mintLimit();

        vm.startPrank(_user1);
        _dollars.burn(tokenIdToBurn);
        vm.stopPrank();

        vm.expectRevert(ARROWS721.ERC721__InvalidToken.selector);
        _dollars.ownerOf(tokenIdToBurn);
    }

    function testUpdateMintPrice() public {
        uint256 newPrice = 200 * 10 ** 18;
        vm.startPrank(_owner);
        _dollars.updateMintPrice(newPrice);
        vm.stopPrank();

        assertEq(_dollars.mintPrice(), newPrice, "Mint price should be updated");
    }

    function testUpdateMintPriceBeforeTokenSet() public {
        vm.startPrank(_owner);
        Dollars newDollars = new Dollars();
        uint256 newPrice = 200 * 10 ** 18;
        vm.expectRevert("Payment token not set");
        newDollars.updateMintPrice(newPrice);
        vm.stopPrank();
    }

    function testUpdateMintLimit() public {
        uint8 newLimit = 20;
        vm.startPrank(_owner);
        _dollars.updateMintLimit(newLimit);
        vm.stopPrank();

        assertEq(_dollars.mintLimit(), newLimit, "Mint limit should be updated");
    }

    function testUpdateMintLimitInvalidZero() public {
        uint8 newLimit = 0;
        vm.startPrank(_owner);
        vm.expectRevert("Invalid limit");
        _dollars.updateMintLimit(newLimit);
        vm.stopPrank();
    }

    function testUpdateMintLimitInvalidTooHigh() public {
        uint8 newLimit = 101;
        vm.startPrank(_owner);
        vm.expectRevert("Invalid limit");
        _dollars.updateMintLimit(newLimit);
        vm.stopPrank();
    }

    function testUpdateOwnerMintSharePercentage() public {
        uint8 newPercentage = 50;
        vm.startPrank(_owner);
        _dollars.updateOwnerMintSharePercentage(newPercentage);
        vm.stopPrank();
        assertEq(_dollars.ownerMintSharePercentage(), newPercentage, "Owner mint share percentage should be updated");
    }

    function testUpdateOwnerMintSharePercentageInvalid() public {
        uint8 newPercentage = 100;
        vm.startPrank(_owner);
        vm.expectRevert("Percentage must be < 100");
        _dollars.updateOwnerMintSharePercentage(newPercentage);
        vm.stopPrank();
    }

    function testUpdateWinnerClaimPercentage() public {
        uint8 newPercentage = 70;
        vm.startPrank(_owner);
        _dollars.updateWinnerClaimPercentage(newPercentage);
        vm.stopPrank();

        assertEq(_dollars.winnerClaimPercentage(), newPercentage, "Winner claim percentage should be updated");
    }

    function testUpdateWinnerClaimPercentageInvalidZero() public {
        uint8 newPercentage = 0;
        vm.startPrank(_owner);
        vm.expectRevert("Percentage must be 1-100");
        _dollars.updateWinnerClaimPercentage(newPercentage);
        vm.stopPrank();
    }

    function testUpdateWinnerClaimPercentageInvalidTooHigh() public {
        uint8 newPercentage = 101;
        vm.startPrank(_owner);
        vm.expectRevert("Percentage must be 1-100");
        _dollars.updateWinnerClaimPercentage(newPercentage);
        vm.stopPrank();
    }

    function testPrizePoolAfterMint() public {
        uint256 totalCost = _dollars.mintPrice() * _dollars.mintLimit();
        uint256 ownerShare = (totalCost * _dollars.ownerMintSharePercentage()) / 100;
        uint256 prizePoolShare = totalCost - ownerShare;

        uint256 initialTotalDeposited = _dollars.getTotalDeposited();
        uint256 initialContractBalance = _paymentToken.balanceOf(address(_dollars));

        _mintTokensForUser(_user1, _dollars.mintLimit());

        uint256 finalTotalDeposited = _dollars.getTotalDeposited();
        uint256 finalContractBalance = _paymentToken.balanceOf(address(_dollars));

        assertEq(finalTotalDeposited - initialTotalDeposited, totalCost, "Total deposited should increase correctly");
        assertEq(
            finalContractBalance - initialContractBalance,
            prizePoolShare,
            "Contract balance should increase by prize pool share"
        );
    }

    function testEmergencyWithdraw() public {
        _mintTokensForUser(_user1, _dollars.mintLimit());

        uint256 contractBalance = _paymentToken.balanceOf(address(_dollars));
        require(contractBalance > 0, "Contract should have funds after mint");

        uint256 initialOwnerBalance = _paymentToken.balanceOf(_owner);

        vm.startPrank(_owner);
        _dollars.emergencyWithdraw();
        vm.stopPrank();

        assertEq(
            _paymentToken.balanceOf(address(_dollars)), 0, "Contract balance should be zero after emergency withdraw"
        );
        assertEq(
            _paymentToken.balanceOf(_owner), initialOwnerBalance + contractBalance, "Owner should receive all funds"
        );
    }

    function testEmergencyWithdrawNoTokenSet() public {
        vm.startPrank(_owner);
        Dollars newDollars = new Dollars();
        vm.expectRevert("Payment token not set");
        newDollars.emergencyWithdraw();
        vm.stopPrank();
    }

    function testEmergencyWithdrawNoFunds() public {
        uint256 initialOwnerBalance = _paymentToken.balanceOf(_owner);

        vm.startPrank(_owner);
        vm.expectRevert("No funds to withdraw");
        _dollars.emergencyWithdraw();
        vm.stopPrank();

        assertEq(_paymentToken.balanceOf(address(_dollars)), 0, "Contract balance remains zero");
        assertEq(_paymentToken.balanceOf(_owner), initialOwnerBalance, "Owner balance unchanged");
    }

    function testTokenURI() public {
        _mintTokensForUser(_user1, 1);
        uint256 tokenId = _dollars.tokenMintId() - 1;

        string memory uri = _dollars.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0, "Token URI should not be empty");
        console.log("Token URI for ID", tokenId, ":", uri);
    }

    function testIsWinningTokenDefaultFalse() public {
        _mintTokensForUser(_user1, 1);
        uint256 tokenId = _dollars.tokenMintId() - 1;

        bool isWinning = _dollars.isWinningToken(tokenId);
        assertFalse(isWinning, "Token should not be winning by default");
    }

    function testClaimPrizeNotWinner() public {
        _mintTokensForUser(_user1, 1);
        uint256 tokenId = _dollars.tokenMintId() - 1;

        vm.startPrank(_user1);
        assertFalse(_dollars.isWinningToken(tokenId), "Token should not be winning");
        vm.stopPrank();
    }

    function testNonOwnerCannotUpdateSettings() public {
        vm.startPrank(_user1);

        vm.expectRevert("Ownable: caller is not the owner");
        _dollars.updateMintPrice(200 * 10 ** 18);

        vm.expectRevert("Ownable: caller is not the owner");
        _dollars.updateMintLimit(20);

        vm.expectRevert("Ownable: caller is not the owner");
        _dollars.updateOwnerMintSharePercentage(50);

        vm.expectRevert("Ownable: caller is not the owner");
        _dollars.updateWinnerClaimPercentage(70);

        vm.expectRevert("Ownable: caller is not the owner");
        _dollars.setPaymentToken(address(0), 100);

        vm.expectRevert("Ownable: caller is not the owner");
        _dollars.emergencyWithdraw();

        vm.stopPrank();
    }

    function testGetColorFunctions() public {
        string memory expectedWinningColor = "029F0E";
        uint8 expectedWinningIndex = 23;

        assertEq(_dollars.getCurrentWinningColor(), expectedWinningColor, "Incorrect current winning color");
        assertEq(
            _dollars.getColorFromIndex(expectedWinningIndex), expectedWinningColor, "Incorrect color from index 23"
        );
        assertEq(
            _dollars.getIndexFromColor(expectedWinningColor), expectedWinningIndex, "Incorrect index from color 029F0E"
        );

        string memory color0 = "2D0157";
        assertEq(_dollars.getColorFromIndex(0), color0, "Incorrect color for index 0");
        assertEq(_dollars.getIndexFromColor(color0), 0, "Incorrect index for color 2D0157");

        string memory color79 = "7D47B7";
        assertEq(_dollars.getColorFromIndex(79), color79, "Incorrect color for index 79");
        assertEq(_dollars.getIndexFromColor(color79), 79, "Incorrect index for color 7D47B7");

        vm.expectRevert("Color not found");
        _dollars.getIndexFromColor("123456");
    }

    function testGetAvailablePrizePool() public {
        assertEq(_dollars.getAvailablePrizePool(), 0, "Initial prize pool should be 0");

        uint256 totalCost = _dollars.mintPrice() * _dollars.mintLimit();
        uint256 ownerShare = (totalCost * _dollars.ownerMintSharePercentage()) / 100;
        uint256 prizePoolShare = totalCost - ownerShare;
        _mintTokensForUser(_user1, _dollars.mintLimit());

        assertEq(_dollars.getAvailablePrizePool(), prizePoolShare, "Prize pool balance incorrect after mint");

        vm.startPrank(_owner);
        _dollars.emergencyWithdraw();
        vm.stopPrank();

        assertEq(_dollars.getAvailablePrizePool(), 0, "Prize pool should be 0 after emergency withdraw");
    }

    function testGetAvailablePrizePoolNoTokenSet() public {
        vm.startPrank(_owner);
        Dollars newDollars = new Dollars();
        vm.stopPrank();

        assertEq(newDollars.getAvailablePrizePool(), 0, "Prize pool should be 0 when token not set");
    }
}
