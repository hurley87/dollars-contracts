// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Arrows.sol";

/**
 * @title Arrows Test
 * @dev Test contract for Arrows contract. This test suite covers all core functionality
 *      including minting, compositing, prize pool management, and admin functions.
 */
contract ArrowsTest is Test {
    Arrows _arrows;
    address _owner;
    address _user1;
    address _user2;
    address _user3;

    uint256 _mintPrice = 0.001 ether;
    uint256 _mintLimit = 10;
    uint256 _winnerPercentage = 60;

    // Add receive function to accept ETH
    receive() external payable {}

    function setUp() public {
        _owner = vm.addr(1); // Use a separate address for owner
        _user1 = vm.addr(2);
        _user2 = vm.addr(3);
        _user3 = vm.addr(4);

        // Deploy the Arrows contract as the owner
        vm.startPrank(_owner);
        _arrows = new Arrows();
        vm.stopPrank();

        // Log addresses
        console.log("Owner address:", _owner);
        console.log("User1 address:", _user1);
        console.log("User2 address:", _user2);
        console.log("User3 address:", _user3);
    }

    function testInitialState() public {
        assertEq(_arrows.mintLimit(), _mintLimit, "Initial mint limit should be 10");
        assertEq(_arrows.mintPrice(), _mintPrice, "Initial mint price should be 0.001 ether");
        assertEq(_arrows.getWinnerPercentage(), _winnerPercentage, "Initial winner percentage should be 60");
        assertEq(_arrows.tokenMintId(), 0, "Initial token mint ID should be 0");
        assertEq(_arrows.getTotalDeposited(), 0, "Initial prize pool should be 0");
        assertEq(_arrows.getTotalWithdrawn(), 0, "Initial owner withdrawn should be 0");
    }

    function testMint() public {
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);

        uint256 initialBalance = _arrows.balanceOf(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        uint256 finalBalance = _arrows.balanceOf(_user1);

        assertEq(finalBalance - initialBalance, _mintLimit, "User should receive correct number of tokens");
        assertEq(_arrows.tokenMintId(), _mintLimit, "Token mint ID should be updated");
        assertEq(_arrows.getTotalDeposited(), _mintPrice * _mintLimit, "Prize pool should be updated");

        vm.stopPrank();
    }

    function testMintInsufficientPayment() public {
        vm.deal(_user1, _mintPrice);
        vm.startPrank(_user1);

        vm.expectRevert("Insufficient payment");
        _arrows.mint{value: _mintPrice}(_user1);

        vm.stopPrank();
    }

    function testComposite() public {
        // Mint tokens for user1
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        uint256 tokenId = 0;
        uint256 burnId = 1;

        // Composite tokens
        vm.startPrank(_user1);
        _arrows.composite(tokenId, burnId);
        vm.stopPrank();

        // Verify token was burned
        vm.expectRevert();
        _arrows.ownerOf(burnId);

        // Verify kept token exists and has been composited
        assertEq(_arrows.ownerOf(tokenId), _user1, "Kept token should still belong to user1");
    }

    function testBurn() public {
        // Mint tokens for user1
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        uint256 tokenId = 0;

        // Burn token
        vm.startPrank(_user1);
        _arrows.burn(tokenId);
        vm.stopPrank();

        // Verify token was burned
        vm.expectRevert();
        _arrows.ownerOf(tokenId);
    }

    function testUpdateMintPrice() public {
        uint256 newPrice = 0.002 ether;
        vm.startPrank(_owner);
        _arrows.updateMintPrice(newPrice);
        vm.stopPrank();

        assertEq(_arrows.mintPrice(), newPrice, "Mint price should be updated");
    }

    function testUpdateMintLimit() public {
        uint8 newLimit = 20;
        vm.startPrank(_owner);
        _arrows.updateMintLimit(newLimit);
        vm.stopPrank();

        assertEq(_arrows.mintLimit(), newLimit, "Mint limit should be updated");
    }

    function testUpdateMintLimitInvalid() public {
        uint8 newLimit = 101;
        vm.startPrank(_owner);
        vm.expectRevert("Invalid limit");
        _arrows.updateMintLimit(newLimit);
        vm.stopPrank();
    }

    function testUpdateWinnerPercentage() public {
        uint8 newPercentage = 70;

        // Warp time forward 1 day to allow winner percentage update
        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(_owner);
        _arrows.updateWinnerPercentage(newPercentage);
        vm.stopPrank();

        assertEq(_arrows.getWinnerPercentage(), newPercentage, "Winner percentage should be updated");
    }

    function testUpdateWinnerPercentageInvalid() public {
        uint8 newPercentage = 100;
        vm.startPrank(_owner);
        vm.expectRevert("Invalid percentage");
        _arrows.updateWinnerPercentage(newPercentage);
        vm.stopPrank();
    }

    function testPrizePoolManagement() public {
        // Mint tokens to fund prize pool
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        uint256 initialPrizePool = _arrows.getTotalDeposited();
        uint256 ownerShare = _arrows.getOwnerShare();
        uint256 winnerShare = _arrows.getWinnerShare();

        assertEq(initialPrizePool, _mintPrice * _mintLimit, "Prize pool should be updated");
        assertEq(ownerShare, (_mintPrice * _mintLimit * 40) / 100, "Owner share should be 40%");
        assertEq(winnerShare, (_mintPrice * _mintLimit * 60) / 100, "Winner share should be 60%");
    }

    function testWithdrawOwnerShare() public {
        // Mint tokens to fund prize pool
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        // Get initial balances
        uint256 initialOwnerBalance = _owner.balance;
        uint256 ownerShare = _arrows.getOwnerShare();

        vm.startPrank(_owner);
        _arrows.withdrawOwnerShare();
        vm.stopPrank();

        assertEq(_owner.balance, initialOwnerBalance + ownerShare, "Owner should receive their share");
        assertEq(_arrows.getTotalWithdrawn(), ownerShare, "Owner withdrawn amount should be updated");
    }

    function testEmergencyWithdraw() public {
        // Mint tokens to fund prize pool
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        // Get contract balance
        uint256 contractBalance = address(_arrows).balance;

        // Get initial owner balance
        uint256 initialOwnerBalance = _owner.balance;

        // No need to transfer ownership since _owner is already the owner

        // Perform emergency withdrawal
        vm.startPrank(_owner);
        _arrows.emergencyWithdraw();
        vm.stopPrank();

        // Verify balances
        assertEq(address(_arrows).balance, 0, "Contract balance should be zero");
        assertEq(_owner.balance, initialOwnerBalance + contractBalance, "Owner should receive all funds");
    }

    function testTokenURI() public {
        // Mint a token
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        string memory uri = _arrows.tokenURI(0);
        assertTrue(bytes(uri).length > 0, "Token URI should not be empty");
    }

    function testIsWinningToken() public {
        // Mint tokens
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        // Test winning token check
        bool isWinning = _arrows.isWinningToken(0);
        assertFalse(isWinning, "Token should not be winning by default");
    }

    function testClaimPrize() public {
        // Mint tokens
        vm.deal(_user1, _mintPrice * _mintLimit);
        vm.startPrank(_user1);
        _arrows.mint{value: _mintPrice * _mintLimit}(_user1);
        vm.stopPrank();

        // Note: This test assumes the token is not a winning token
        // In a real scenario, you would need to mint a token that meets the winning criteria
        vm.startPrank(_user1);
        vm.expectRevert("Not a winning token");
        _arrows.claimPrize(0);
        vm.stopPrank();
    }

    function testNonOwnerCannotUpdateSettings() public {
        vm.startPrank(_user1);

        vm.expectRevert();
        _arrows.updateMintPrice(0.002 ether);

        vm.expectRevert();
        _arrows.updateMintLimit(20);

        vm.expectRevert();
        _arrows.updateWinnerPercentage(70);

        vm.expectRevert();
        _arrows.withdrawOwnerShare();

        vm.expectRevert();
        _arrows.emergencyWithdraw();

        vm.stopPrank();
    }
}