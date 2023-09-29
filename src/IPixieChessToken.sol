// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPixieChessToken {
    function mint(address account, uint256 id, uint256 amount, bytes memory data) external;

    function setURI(uint256 tokenId, string memory tokenURI) external;

    function setBaseURI(string memory baseURI) external;
}
