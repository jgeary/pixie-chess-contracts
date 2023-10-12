// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AccessControl } from "openzeppelin/access/AccessControl.sol";
import { IPixieChessToken } from "./IPixieChessToken.sol";

contract PixieChessAuctionMinter is AccessControl {
    bytes32 public constant AUCTION_MANAGER_ROLE = keccak256("AUCTION_MANAGER_ROLE");
    uint16 public constant MIN_DURATION = 1 hours;
    uint16 public constant TIME_BUFFER = 15 minutes;
    uint8 public constant MIN_BID_INCREMENT_PERCENTAGE = 10;

    struct Auction {
        uint256 tokenId;
        uint96 reservePrice;
        uint96 highestBid;
        uint32 duration;
        uint32 startTime;
        address highestBidder;
    }

    address public tokenAddress;
    address payable public fundsRecipient;
    mapping(uint256 id => Auction auction) public auctions;

    uint256 internal _auctionIdCounter;

    event AuctionCreated(uint256 auctionId, uint256 tokenId, uint96 reservePrice, uint32 duration, uint32 startTime);
    event AuctionCanceled(uint256 auctionId);
    event Bid(uint256 auctionId, address bidder, uint256 amount, uint32 duration);
    event AuctionFinalized(uint256 auctionId, address winner, uint256 amount);
    event FundsRecipientSet(address oldFundsRecipient, address newFundsRecipient);

    constructor(address payable _admin, address _tokenAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(AUCTION_MANAGER_ROLE, _admin);
        fundsRecipient = _admin;
        tokenAddress = _tokenAddress;
    }

    function createAuction(
        uint256 tokenId,
        uint96 reservePrice,
        uint32 duration,
        uint32 startTime
    )
        external
        onlyRole(AUCTION_MANAGER_ROLE)
    {
        require(duration >= MIN_DURATION, "Auction: invalid duration");
        require(startTime >= block.timestamp, "Auction: invalid start time");

        uint256 auctionId = _auctionIdCounter;
        _auctionIdCounter += 1;

        auctions[auctionId] = Auction({
            tokenId: tokenId,
            reservePrice: reservePrice,
            highestBid: 0,
            highestBidder: address(0),
            duration: duration,
            startTime: startTime
        });

        emit AuctionCreated(auctionId, tokenId, reservePrice, duration, startTime);
    }

    function cancelAuction(uint256 auctionId) external onlyRole(AUCTION_MANAGER_ROLE) {
        Auction storage auction = auctions[auctionId];

        // if auction doesn't exist, revert with error message
        if (auction.duration == 0) {
            revert("Auction: Auction does not exist");
        }

        address refundRecipient = auction.highestBidder;
        uint256 refundAmount = auction.highestBid;

        delete auctions[auctionId];

        if (refundRecipient != address(0) && refundAmount != 0) {
            payable(refundRecipient).transfer(refundAmount);
        }

        emit AuctionCanceled(auctionId);
    }

    function bid(uint256 auctionId) external payable {
        Auction storage auction = auctions[auctionId];

        // if auction doesn't exist, revert with error message
        if (auction.duration == 0) {
            revert("Auction: Auction does not exist");
        }

        // if auction has already ended, revert with error message
        if (auction.startTime + auction.duration < block.timestamp) {
            revert("Auction: Auction already ended");
        }

        address refundRecipient = auction.highestBidder;
        uint256 refundAmount = auction.highestBid;

        if (auction.highestBid == 0) {
            require(msg.value >= auction.reservePrice, "Auction: Bid must meet reserve");
        } else {
            uint256 minBidIncrement = (auction.highestBid * MIN_BID_INCREMENT_PERCENTAGE) / 100;
            require(msg.value >= auction.highestBid + minBidIncrement, "Auction: Bid increase too small");
        }

        // if remaining time is less than the time buffer, extend the duration by the time buffer
        uint256 timeRemaining = auction.startTime + auction.duration - block.timestamp;
        if (timeRemaining < TIME_BUFFER) {
            auction.duration += uint32(TIME_BUFFER - timeRemaining);
        }

        // set the new highest bidder
        auction.highestBid = uint96(msg.value);
        auction.highestBidder = msg.sender;

        // transfer the previous highest bid to the previous highest bidder
        if (refundRecipient != address(0) && refundAmount != 0) {
            payable(refundRecipient).transfer(refundAmount);
        }

        emit Bid(auctionId, msg.sender, msg.value, auction.duration);
    }

    function finalizeAuction(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];

        if (auction.duration == 0) {
            revert("Auction: Auction does not exist");
        }
        if (auction.startTime + auction.duration > block.timestamp) {
            revert("Auction: Auction not yet ended");
        }
        if (auction.highestBidder == address(0)) {
            revert("Auction: Auction has no winner");
        }

        // mint the token to the highest bidder
        IPixieChessToken(tokenAddress).mint(auction.highestBidder, auction.tokenId, 1, "");

        // transfer the ETH to the funds recipient
        fundsRecipient.transfer(auction.highestBid);

        emit AuctionFinalized(auctionId, auction.highestBidder, auction.highestBid);

        delete auctions[auctionId];
    }

    function setFundsRecipient(address payable _fundsRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit FundsRecipientSet(fundsRecipient, _fundsRecipient);
        fundsRecipient = _fundsRecipient;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
