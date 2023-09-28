// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC1155Upgradeable } from "openzeppelin-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { ERC1155URIStorageUpgradeable } from
    "openzeppelin-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import { AccessControlUpgradeable } from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract PixieChessToken is
    ERC1155URIStorageUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function initialize() public nonReentrant onlyInitializing {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __ERC1155URIStorage_init();
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external onlyRole(MINTER_ROLE) {
        _mint(account, id, amount, data);
    }

    function setURI(uint256 tokenId, string memory tokenURI) external onlyRole(METADATA_ROLE) {
        _setURI(tokenId, tokenURI);
    }

    function setBaseURI(string memory baseURI) external onlyRole(METADATA_ROLE) {
        _setBaseURI(baseURI);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address _newImpl) internal view override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
