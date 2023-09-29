// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC1155 } from "openzeppelin/token/ERC1155/IERC1155.sol";
import { AccessControl } from "openzeppelin/access/AccessControl.sol";
import { IPixieChessToken } from "./IPixieChessToken.sol";

contract PixieChessAuctionMinter is AccessControl {
    bytes32 public constant AUCTION_MANAGER_ROLE = keccak256("AUCTION_MANAGER_ROLE");
    uint16 constant TIME_BUFFER = 15 minutes;
    uint8 constant MIN_BID_INCREMENT_PERCENTAGE = 10;

    struct Auction {
        uint256 tokenId;
        uint96 reservePrice;
        uint96 highestBid;
        uint32 duration;
        uint32 startTime;
        address highestBidder;
        uint32 firstBidTime;
    }

    address public tokenAddress;
    address public fundsRecipient;
    uint256 internal auctionIdCounter;

    mapping(uint256 => Auction) public auctions;

    event AuctionCreated(uint256 auctionId, uint256 tokenId, uint96 reservePrice, uint32 duration, uint32 startTime);
    event AuctionCanceled(uint256 auctionId);
    event Bid(uint256 auctionId, address bidder, uint256 amount, uint32 duration);
    event AuctionFinalized(uint256 auctionId, address winner, uint256 amount);

    constructor(address multisig, address _tokenAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, multisig);
        _grantRole(AUCTION_MANAGER_ROLE, multisig);
        fundsRecipient = multisig;
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
        require(duration >= 1 hours, "Auction: Duration must be at least 1 minute");
        require(startTime >= block.timestamp, "Auction: Start time must be in the future");

        uint256 auctionId = auctionIdCounter;
        auctionIdCounter += 1;

        auctions[auctionId] = Auction({
            tokenId: tokenId,
            reservePrice: reservePrice,
            highestBid: 0,
            highestBidder: address(0),
            duration: duration,
            startTime: startTime,
            firstBidTime: 0
        });

        emit AuctionCreated(auctionId, tokenId, reservePrice, duration, startTime);
    }

    function cancelAuction(uint256 auctionId) external onlyRole(AUCTION_MANAGER_ROLE) {
        Auction storage auction = auctions[auctionId];

        // if auction doesn't exist, revert with error message
        if (auction.duration == 0) {
            revert("Auction: Auction does not exist");
        }

        // if there is a bid on the auction, refund ETH to the highest bidder
        if (auction.highestBidder != address(0) && auction.highestBid != 0) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        delete auctions[auctionId];

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

        if (auction.firstBidTime != 0) {
            uint256 minBidIncrement = (auction.highestBid * MIN_BID_INCREMENT_PERCENTAGE) / 100;
            require(
                msg.value >= auction.highestBid + minBidIncrement,
                "Auction: Bid must be at least 10% higher than previous bid"
            );
            // refund previous highest bidder
            payable(auction.highestBidder).transfer(auction.highestBid);
        } else {
            require(msg.value >= auction.reservePrice, "Auction: Bid must be at least reserve price");
            auction.firstBidTime = uint32(block.timestamp);
        }

        // if remaining time is less than the time buffer, extend the duration by the time buffer
        uint256 timeRemaining = auction.startTime + auction.duration - block.timestamp;
        if (timeRemaining < TIME_BUFFER) {
            auction.duration += uint32(TIME_BUFFER - timeRemaining);
        }

        // set the new highest bidder
        auction.highestBid = uint96(msg.value);
        auction.highestBidder = msg.sender;

        emit Bid(auctionId, msg.sender, msg.value, auction.duration);
    }

    function finalizeAuction(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];

        if (auction.duration == 0) {
            revert("Auction: Auction doesn't exist");
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
        payable(fundsRecipient).transfer(auction.highestBid);

        emit AuctionFinalized(auctionId, auction.highestBidder, auction.highestBid);

        delete auctions[auctionId];
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
