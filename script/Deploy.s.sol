// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { PixieChessAuctionMinter } from "../src/PixieChessAuctionMinter.sol";
import { PixieChessToken } from "../src/PixieChessToken.sol";

contract Deploy is Script {
    function run() public {
        address deployer = vm.envAddress("DEPLOYER");
        address payable multisig = payable(vm.envAddress("MULTISIG"));

        vm.startBroadcast(deployer);

        PixieChessToken tokenImpl = new PixieChessToken();
        PixieChessToken token = PixieChessToken(address(new ERC1967Proxy(tokenImpl, "")));
        token.initialize(multisig);

        PixieChessAuctionMinter auction = new PixieChessAuctionMinter(multisig, address(token));

        vm.stopBroadcast();

        console2.log("PixieChessToken implementation deployed at: ", address(tokenImpl));
        console2.log("PixieChessToken deployed at: ", address(token));
        console2.log("PixieChessAuctionMinter deployed at: ", address(auction));

        // manually (for now) grant the token minter role to the auction contract
    }
}
