// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { PixieChessToken } from "../src/PixieChessToken.sol";

contract PixieChessTokenTest is Test {
    PixieChessToken public pixieChessToken;

    address payable public admin = payable(address(1));
    address public tokenRecipient = address(2);

    function setUp() public virtual {
        pixieChessToken = PixieChessToken(address(new ERC1967Proxy(address(new PixieChessToken()), "")));
        pixieChessToken.initialize(admin);
    }

    function testMint() public {
        vm.expectRevert();
        pixieChessToken.mint(tokenRecipient, 1, 1, "");

        vm.prank(admin);
        pixieChessToken.mint(tokenRecipient, 1, 1, "");
        assertEq(pixieChessToken.balanceOf(tokenRecipient, 1), 1);
    }

    function testMintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3;
        amounts[1] = 4;

        vm.expectRevert();
        pixieChessToken.mintBatch(tokenRecipient, ids, amounts, "");

        vm.prank(admin);
        pixieChessToken.mintBatch(tokenRecipient, ids, amounts, "");
        assertEq(pixieChessToken.balanceOf(tokenRecipient, 1), 3);
        assertEq(pixieChessToken.balanceOf(tokenRecipient, 2), 4);
    }

    function testSetURI() public {
        vm.expectRevert();
        pixieChessToken.setURI(1, "token1Uri");

        vm.prank(admin);
        pixieChessToken.setURI(1, "token1Uri");
        assertEq(pixieChessToken.uri(1), "token1Uri");
    }

    function testSetBaseURI() public {
        assertEq(pixieChessToken.uri(1), "");
        vm.prank(admin);
        pixieChessToken.setURI(1, "1.json");

        vm.expectRevert();
        pixieChessToken.setBaseURI("https://pixiechess.com/");

        vm.prank(admin);
        pixieChessToken.setBaseURI("https://pixiechess.com/");
        assertEq(pixieChessToken.uri(1), "https://pixiechess.com/1.json");
    }
}
