// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

/// @title ProjectPresale
/// @notice Multi-stage presale with ETH & USDT contributions and post-sale claim.
/// @dev Prices are in USD per token (1e18). USDT is treated as 6 decimals (typical).
contract ProjectPresale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Stage {
        uint256 usdPerToken;   // USD * 1e18 per 1 token unit (10^tokenDecimals)
        uint256 capTokens;     // max tokens for this stage (token units)
        uint256 soldTokens;    // sold tokens in this stage (token units)
        uint64  startTime;     // 0 for "start immediately"
        uint64  endTime;       // 0 for "no time end"
    }

    // Immutable configuration
    IERC20 public immutable token;
    uint8  public immutable tokenDecimals;
    uint256 public immutable scale; // 10^tokenDecimals
    IERC20 public immutable usdt;   // 6 decimals typical; we read decimals dynamically
    uint8  public immutable usdtDecimals;
    address public immutable treasury;

    // Optional oracle (ETH/USD). If zero address, ETH path is disabled.
    IAggregatorV3 public immutable ethUsdOracle;

    // State
    Stage[] private _stages;
    uint256 public currentStage;        // index into _stages
    uint256 public totalSold;           // across all stages
    mapping(address => uint256) public purchased; // claimable tokens per user

    bool public paused;
    bool public claimEnabled;

    // Limits (optional; set 0 to disable)
    uint256 public minBuyUsd; // in 1e18 USD
    uint256 public maxBuyUsd; // in 1e18 USD
    uint256 public perWalletCap; // in token units

    // Events
    event Purchased(address indexed buyer, uint256 tokens, uint256 paidEth, uint256 paidUsdt);
    event Claimed(address indexed buyer, uint256 amount);
    event StageAdvanced(uint256 newStage);
    event Paused(bool status);
    event ClaimEnabled(bool status);
    event LimitsUpdated(uint256 minBuyUsd, uint256 maxBuyUsd, uint256 perWalletCap);

    constructor(
        address token_,
        address usdt_,
        address treasury_,
        address ethUsdOracle_, // set to address(0) to disable ETH path
        Stage[] memory stages_
    ) Ownable(msg.sender) {
        require(token_ != address(0) && usdt_ != address(0) && treasury_ != address(0), "zero");
        require(stages_.length > 0, "no stages");

        token = IERC20(token_);
        tokenDecimals = IERC20Metadata(token_).decimals();
        scale = 10 ** uint256(tokenDecimals);

        usdt = IERC20(usdt_);
        usdtDecimals = IERC20Metadata(usdt_).decimals();
        treasury = treasury_;

        ethUsdOracle = ethUsdOracle_ == address(0) ? IAggregatorV3(address(0)) : IAggregatorV3(ethUsdOracle_);

        for (uint256 i = 0; i < stages_.length; ++i) {
            require(stages_[i].usdPerToken > 0 && stages_[i].capTokens > 0, "stage");
            _stages.push(stages_[i]);
        }
    }

    /* ============================ Admin ============================ */

    function setPaused(bool v) external onlyOwner {
        paused = v;
        emit Paused(v);
    }

    function setClaimEnabled(bool v) external onlyOwner {
        claimEnabled = v;
        emit ClaimEnabled(v);
    }

    /// @notice Optional buy limits (set 0 to disable each)
    function setLimits(uint256 minUsd, uint256 maxUsd, uint256 perWalletCapTokens) external onlyOwner {
        require(minUsd <= maxUsd || maxUsd == 0, "limits");
        minBuyUsd = minUsd;
        maxBuyUsd = maxUsd;
        perWalletCap = perWalletCapTokens;
        emit LimitsUpdated(minUsd, maxUsd, perWalletCapTokens);
    }

    /// @notice Withdraw collected ETH to treasury
    function withdrawEth() external onlyOwner nonReentrant {
        (bool ok, ) = payable(treasury).call{value: address(this).balance}("");
        require(ok, "withdraw");
    }

    /* ============================ Views ============================ */

    function stagesCount() external view returns (uint256) {
        return _stages.length;
    }

    function getStage(uint256 i) external view returns (Stage memory) {
        return _stages[i];
    }

    function claimable(address user) external view returns (uint256) {
        return purchased[user];
    }

    /* ============================ Buying ============================ */

    /// @notice Buy with ETH; requires oracle set.
    function buyWithEth() external payable nonReentrant {
        require(!paused, "paused");
        require(address(ethUsdOracle) != address(0), "eth disabled");
        require(msg.value > 0, "no eth");

        // Convert ETH to USD (1e18)
        uint256 usdAmount = _ethToUsd(msg.value);
        _enforceUsdLimits(usdAmount);

        // Allocate USD across stages → tokens
        (uint256 tokensOut, ) = _allocateAcrossStages(usdAmount);
        _finalizePurchase(tokensOut, msg.value, 0);
    }

    /// @notice Buy with USDT (spender must approve this contract).
    /// @param usdtAmount Amount of USDT in USDT decimals (usually 6)
    function buyWithUsdt(uint256 usdtAmount) external nonReentrant {
        require(!paused, "paused");
        require(usdtAmount > 0, "no usdt");

        // Convert USDT amount to USD (1e18) respecting USDT decimals
        uint256 usdAmount = _toUsd1e18(usdtAmount, usdtDecimals);
        _enforceUsdLimits(usdAmount);

        (uint256 tokensOut, ) = _allocateAcrossStages(usdAmount);

        // Pull USDT directly to treasury
        usdt.safeTransferFrom(msg.sender, treasury, usdtAmount);
        _finalizePurchase(tokensOut, 0, usdtAmount);
    }

    /* ============================ Claim ============================ */

    function claim() external nonReentrant {
        require(claimEnabled, "claim off");
        uint256 amount = purchased[msg.sender];
        require(amount > 0, "none");
        purchased[msg.sender] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    /* ============================ Internals ============================ */

    function _finalizePurchase(uint256 tokensOut, uint256 ethIn, uint256 usdtIn) internal {
        require(tokensOut > 0, "tiny");
        if (perWalletCap != 0) {
            require(purchased[msg.sender] + tokensOut <= perWalletCap, "wallet cap");
        }

        purchased[msg.sender] += tokensOut;
        totalSold += tokensOut;

        emit Purchased(msg.sender, tokensOut, ethIn, usdtIn);
    }

    /// @dev Allocate USD across current and subsequent stages until fully consumed or stages end.
    /// @return tokensOut total tokens purchased, usdUsed total USD used (1e18)
    function _allocateAcrossStages(uint256 usdBudget)
        internal
        returns (uint256 tokensOut, uint256 usdUsed)
    {
        uint256 i = currentStage;
        uint256 n = _stages.length;
        uint256 remainingUsd = usdBudget;

        while (i < n && remainingUsd > 0) {
            Stage storage s = _stages[i];

            // auto-advance by time if needed
            if (s.endTime != 0 && block.timestamp > s.endTime) {
                unchecked { ++i; }
                continue;
            }
            if (s.startTime != 0 && block.timestamp < s.startTime) {
                // not started yet; stop allocation
                break;
            }

            uint256 stageRemainingTokens = s.capTokens - s.soldTokens;
            if (stageRemainingTokens == 0) {
                unchecked { ++i; }
                continue;
            }

            // tokens affordable with the remaining USD at this stage
            // usdPerToken is USD*1e18 per token unit
            uint256 affordableTokens = (remainingUsd * scale) / s.usdPerToken;

            if (affordableTokens == 0) break; // budget too small for 1 token at this stage

            uint256 takeTokens = affordableTokens > stageRemainingTokens
                ? stageRemainingTokens
                : affordableTokens;

            // USD actually used for these tokens
            uint256 usdForThis = (takeTokens * s.usdPerToken) / scale;

            s.soldTokens += takeTokens;
            tokensOut += takeTokens;
            usdUsed += usdForThis;
            remainingUsd -= usdForThis;

            // If this stage is now filled, attempt to auto-advance
            if (s.soldTokens >= s.capTokens) {
                unchecked { ++i; }
                if (i != currentStage) {
                    currentStage = i;
                    emit StageAdvanced(i);
                }
            } else {
                // still in the same stage; stop if we couldn’t spend more
                if (affordableTokens <= takeTokens) break;
            }
        }

        require(tokensOut > 0, "sold out");
    }

    function _enforceUsdLimits(uint256 usdAmount) internal view {
        if (minBuyUsd != 0)  require(usdAmount >= minBuyUsd, "min");
        if (maxBuyUsd != 0)  require(usdAmount <= maxBuyUsd, "max");
    }

    /// @dev Convert ETH amount to USD 1e18 using Chainlink aggregator decimals.
    function _ethToUsd(uint256 weiAmount) internal view returns (uint256) {
        ( , int256 answer, , , ) = ethUsdOracle.latestRoundData();
        require(answer > 0, "oracle");
        uint8 d = ethUsdOracle.decimals(); // e.g., 8
        // weiAmount (1e18) * price(1eD) -> USD*1e(18+D); normalize to 1e18
        // usd = wei * price / 1e18 * 1e(18-D)  => combine to avoid precision loss:
        uint256 price = uint256(answer);
        if (d >= 18) {
            return (weiAmount * price) / (10 ** (d));
        } else {
            // scale price up to 1e18 world
            uint256 scaled = price * (10 ** (18 - d));
            return (weiAmount * scaled) / 1e18;
        }
    }

    /// @dev Convert an amount with `srcDecimals` to USD 1e18 (USDT path treats 1 USDT = $1).
    function _toUsd1e18(uint256 amount, uint8 srcDecimals) internal pure returns (uint256) {
        if (srcDecimals == 18) return amount;
        if (srcDecimals < 18)  return amount * (10 ** (18 - srcDecimals));
        return amount / (10 ** (srcDecimals - 18));
    }

    receive() external payable {}
}
