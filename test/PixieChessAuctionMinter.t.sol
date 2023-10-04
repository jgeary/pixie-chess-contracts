// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { PixieChessToken } from "../src/PixieChessToken.sol";
import { PixieChessAuctionMinter } from "../src/PixieChessAuctionMinter.sol";

contract PixieChessAuctionMinterTest is Test {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    PixieChessToken public pixieChessToken;
    PixieChessAuctionMinter public pixieChessAuctionMinter;

    address payable public admin = payable(address(0x100));

    address public bidder1 = address(0x101);
    address public bidder2 = address(0x102);

    event AuctionCreated(uint256 auctionId, uint256 tokenId, uint96 reservePrice, uint32 duration, uint32 startTime);
    event AuctionCanceled(uint256 auctionId);
    event Bid(uint256 auctionId, address bidder, uint256 amount, uint32 duration);
    event AuctionFinalized(uint256 auctionId, address winner, uint256 amount);
    event FundsRecipientSet(address oldFundsRecipient, address newFundsRecipient);

    function setUp() public virtual {
        pixieChessToken = PixieChessToken(address(new ERC1967Proxy(address(new PixieChessToken()), "")));
        pixieChessToken.initialize(admin);

        pixieChessAuctionMinter = new PixieChessAuctionMinter(admin, address(pixieChessToken));

        vm.prank(admin);
        pixieChessToken.grantRole(MINTER_ROLE, address(pixieChessAuctionMinter));

        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);
    }

    function testCreateAuctionOnlyAdmin() public {
        vm.expectRevert();
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.startPrank(admin);
        vm.expectEmit();
        emit AuctionCreated(0, 1, 0, 1 hours, uint32(block.timestamp));
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        // test that auctionId is incremented
        vm.expectEmit();
        emit AuctionCreated(1, 1, 0, 1 hours, uint32(block.timestamp));
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));
        vm.stopPrank();
    }

    function testCreateAuctionValidatesDuration() public {
        vm.expectRevert(bytes("Auction: invalid duration"));
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours - 1, uint32(block.timestamp) + 1);
    }

    function testCreateAuctionValidatesStartTime() public {
        vm.expectRevert(bytes("Auction: invalid duration"));
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours - 1, uint32(block.timestamp) + 1);
    }

    function testCancelAuctionOnlyAdmin() public {
        vm.startPrank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.expectEmit();
        emit AuctionCanceled(0);
        pixieChessAuctionMinter.cancelAuction(0);
        vm.stopPrank();
    }

    function testCancelAuctionSucceedsWithFutureAuction() public {
        vm.startPrank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp + 1 days));

        vm.expectEmit();
        emit AuctionCanceled(0);
        pixieChessAuctionMinter.cancelAuction(0);
        vm.stopPrank();
    }

    function testCancelAuctionSucceedsWithLiveAuctionAndRefundsBidder() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
        assertEq(bidder1.balance, 9.9 ether);

        vm.prank(admin);
        vm.expectEmit();
        emit AuctionCanceled(0);
        pixieChessAuctionMinter.cancelAuction(0);
        assertEq(bidder1.balance, 10 ether);

        vm.prank(bidder2);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.bid{ value: 0.2 ether }(0);
    }

    function testCancelAuctionSucceedsWithUnfinalizedAuctionAndRefundsBidder() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
        assertEq(bidder1.balance, 9.9 ether);

        // confirm auction is over
        vm.warp(block.timestamp + 2 hours);
        vm.prank(bidder2);
        vm.expectRevert(bytes("Auction: Auction already ended"));
        pixieChessAuctionMinter.bid{ value: 0.2 ether }(0);

        vm.prank(admin);
        vm.expectEmit();
        emit AuctionCanceled(0);
        pixieChessAuctionMinter.cancelAuction(0);
        assertEq(bidder1.balance, 10 ether);
    }

    function testCancelAuctionRevertsForNonexistantAuction() public {
        vm.prank(admin);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.cancelAuction(10);
    }

    function testCancelAuctionRevertsForCanceledAuction() public {
        vm.startPrank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));
        pixieChessAuctionMinter.cancelAuction(0);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.cancelAuction(0);
        vm.stopPrank();
    }

    function testCancelAuctionRevertsForFinalizedAuction() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);

        vm.startPrank(admin);
        vm.warp(block.timestamp + 2 hours);
        pixieChessAuctionMinter.finalizeAuction(0);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.cancelAuction(0);
        vm.stopPrank();
    }

    function testBidSucceedsForLiveAuction() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        vm.expectEmit();
        emit Bid(0, bidder1, 0.1 ether, 1 hours);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
    }

    function testBidRevertsForNonexistantAuction() public {
        vm.prank(bidder1);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
    }

    function testBidRevertsForCanceledAuction() public {
        vm.startPrank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));
        pixieChessAuctionMinter.cancelAuction(0);
        vm.stopPrank();

        vm.prank(bidder1);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
    }

    function testBidRevertsForFinalizedAuction() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);

        vm.prank(admin);
        vm.warp(block.timestamp + 2 hours);
        pixieChessAuctionMinter.finalizeAuction(0);

        vm.prank(bidder2);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.bid{ value: 0.2 ether }(0);
    }

    function testBidRevertsForEndedAuction() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.warp(block.timestamp + 2 hours);
        vm.prank(bidder1);
        vm.expectRevert(bytes("Auction: Auction already ended"));
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
    }

    function testBidRequiresFirstBidToMeetReservePrice() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0.1 ether, 1 hours, uint32(block.timestamp));

        vm.startPrank(bidder1);
        vm.expectRevert(bytes("Auction: Bid must meet reserve"));
        pixieChessAuctionMinter.bid{ value: 0.09 ether }(0);

        vm.expectEmit();
        emit Bid(0, bidder1, 0.1 ether, 1 hours);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
        vm.stopPrank();
    }

    function testBidRequiresBidsToMeetMinimumPercentIncrease() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 1 ether, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 1 ether }(0);

        vm.startPrank(bidder2);
        vm.expectRevert(bytes("Auction: Bid increase too small"));
        pixieChessAuctionMinter.bid{ value: 1.09 ether }(0);
        vm.expectEmit();
        emit Bid(0, bidder2, 1.1 ether, 1 hours);
        pixieChessAuctionMinter.bid{ value: 1.1 ether }(0);
        vm.stopPrank();
    }

    function testBidRefundsPreviousBidder() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
        assertEq(bidder1.balance, 9.9 ether);

        vm.prank(bidder2);
        pixieChessAuctionMinter.bid{ value: 0.2 ether }(0);
        assertEq(bidder1.balance, 10 ether);
    }

    function testBidExtendsDurationByTimeBuffer() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        vm.warp(block.timestamp + 1 hours - 5 minutes); // 5 minutes before auction ends
        vm.expectEmit();
        emit Bid(0, bidder1, 0.1 ether, 1 hours + 10 minutes); // 15 minutes from now
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
    }

    function testFinalizeAuctionRevertsForNonexistantAuction() public {
        vm.prank(admin);
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.finalizeAuction(0);
    }

    function testFinalizeAuctionRevertsForCanceledAuction() public {
        vm.startPrank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));
        pixieChessAuctionMinter.cancelAuction(0);
        vm.stopPrank();
        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.finalizeAuction(0);
    }

    function testFinalizeAuctionRevertsForFinalizedAuction() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);

        vm.warp(block.timestamp + 2 hours);
        pixieChessAuctionMinter.finalizeAuction(0);

        vm.expectRevert(bytes("Auction: Auction does not exist"));
        pixieChessAuctionMinter.finalizeAuction(0);
    }

    function testFinalizeAuctionRevertsForLiveAuction() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));
        vm.expectRevert(bytes("Auction: Auction not yet ended"));
        pixieChessAuctionMinter.finalizeAuction(0);
    }

    function testFinalizeAuctionRevertsIfNoBidders() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0, 1 hours, uint32(block.timestamp));
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(bytes("Auction: Auction has no winner"));
        pixieChessAuctionMinter.finalizeAuction(0);
    }

    function testFinalizeAuctionMintsTokenAndTransfersFunds() public {
        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0.1 ether, 1 hours, uint32(block.timestamp));

        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);

        vm.warp(block.timestamp + 2 hours);
        vm.expectEmit();
        emit AuctionFinalized(0, bidder1, 0.1 ether);
        pixieChessAuctionMinter.finalizeAuction(0);

        assertEq(pixieChessToken.balanceOf(bidder1, 1), 1);
        assertEq(admin.balance, 0.1 ether);
    }

    function testSetFundsRecipientOnlyAdmin() public {
        vm.expectRevert();
        pixieChessAuctionMinter.setFundsRecipient(payable(address(0x103)));

        vm.prank(admin);
        vm.expectEmit();
        emit FundsRecipientSet(admin, address(0x103));
        pixieChessAuctionMinter.setFundsRecipient(payable(address(0x103)));

        vm.prank(admin);
        pixieChessAuctionMinter.createAuction(1, 0.1 ether, 1 hours, uint32(block.timestamp));
        vm.prank(bidder1);
        pixieChessAuctionMinter.bid{ value: 0.1 ether }(0);
        vm.warp(block.timestamp + 2 hours);
        pixieChessAuctionMinter.finalizeAuction(0);

        assertEq(address(0x103).balance, 0.1 ether);
    }
}
