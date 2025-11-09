// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ProjectToken
/// @notice Fixed-supply ERC20 with optional holder burn; no minting after deployment.
contract ProjectToken is ERC20, ERC20Burnable, Ownable {
    uint8 private immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply,
        address initialRecipient
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(initialRecipient != address(0), "recipient=0");
        _decimals = decimals_;
        _mint(initialRecipient, initialSupply);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
