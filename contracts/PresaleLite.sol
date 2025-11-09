// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Minimal ETH-only presale for testing
/// @notice Flat price, single stage, claim after enable; no oracle/LP/USDT.
contract PresaleLite is Ownable, ReentrancyGuard {
    IERC20 public immutable token;
    uint8 public immutable tokenDecimals;
    address public immutable treasury;

    // price in wei per 1 token (10^decimals units)
    uint256 public immutable priceWeiPerToken;
    // max tokens available for sale (in token units, 10^decimals)
    uint256 public immutable saleCap;

    mapping(address => uint256) public purchased;
    uint256 public sold;

    bool public paused;
    bool public claimEnabled;

    event Purchased(address indexed buyer, uint256 ethIn, uint256 tokens);
    event Claimed(address indexed buyer, uint256 amount);
    event Paused(bool status);
    event ClaimEnabled(bool status);

    constructor(
        address token_,
        address treasury_,
        uint256 priceWeiPerToken_,
        uint256 saleCap_
    ) Ownable(msg.sender) {
        require(token_ != address(0), "token");
        require(treasury_ != address(0), "treasury");
        require(priceWeiPerToken_ > 0, "price");
        require(saleCap_ > 0, "cap");

        token = IERC20(token_);
        tokenDecimals = IERC20Metadata(token_).decimals();
        treasury = treasury_;
        priceWeiPerToken = priceWeiPerToken_;
        saleCap = saleCap_;
    }

    function setPaused(bool v) external onlyOwner {
        paused = v;
        emit Paused(v);
    }

    function setClaimEnabled(bool v) external onlyOwner {
        claimEnabled = v;
        emit ClaimEnabled(v);
    }

    function buy() external payable nonReentrant {
        require(!paused, "paused");
        require(msg.value > 0, "no eth");

        // tokens = (msg.value * 10^decimals) / priceWeiPerToken
        uint256 scale = 10 ** uint256(tokenDecimals);
        uint256 tokensOut = (msg.value * scale) / priceWeiPerToken;
        require(tokensOut > 0, "tiny buy");

        require(sold + tokensOut <= saleCap, "sold out");
        purchased[msg.sender] += tokensOut;
        sold += tokensOut;

        emit Purchased(msg.sender, msg.value, tokensOut);
    }

    /// @notice Pull-based: users claim tokens after claim is enabled
    function claim() external nonReentrant {
        require(claimEnabled, "claim off");
        uint256 amount = purchased[msg.sender];
        require(amount > 0, "none");
        purchased[msg.sender] = 0;

        require(token.transfer(msg.sender, amount), "transfer failed");
        emit Claimed(msg.sender, amount);
    }

    /// @notice Withdraw collected ETH to treasury
    function withdraw() external onlyOwner nonReentrant {
        (bool ok, ) = payable(treasury).call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // Convenience views
    function claimable(address user) external view returns (uint256) {
        return purchased[user];
    }

    receive() external payable {} // allow ether
}
