// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ProjectToken
/// @notice Fixed-supply ERC-20 with optional burn and an initial-trade gate.
/// @dev Total supply: 10 000 000 000 * 10¹⁸.  No minting after deployment.
contract ProjectToken is ERC20, ERC20Burnable, Ownable {
    uint8 private constant _DECIMALS = 18;
    uint256 private constant _TOTAL_SUPPLY = 10_000_000_000 * 10 ** _DECIMALS;

    /// @dev LP / trading pair address used for the first-buy gate.
    address public tradingPair;
    bool public firstBuyDone;

    event TradingPairSet(address indexed pair);
    event FirstBuyCompleted(address indexed by);

    constructor(
        string memory name_,
        string memory symbol_,
        address initialRecipient
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(initialRecipient != address(0), "recipient=0");
        _mint(initialRecipient, _TOTAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    /// @notice Set the DEX pair used for the first-buy protection.
    function setTradingPair(address pair) external onlyOwner {
        require(pair != address(0), "pair=0");
        tradingPair = pair;
        emit TradingPairSet(pair);
    }

    /// @dev OZ v5 `_update` hook used instead of manual `_transfer`.
    function _update(address from, address to, uint256 amount) internal override {
        // First-buy gate: the first purchase from the pair must be executed by the owner.
        if (!firstBuyDone && from == tradingPair) {
            require(tx.origin == owner(), "first buy: not owner");
            firstBuyDone = true;
            emit FirstBuyCompleted(owner());
        }
        super._update(from, to, amount);
    }
}
