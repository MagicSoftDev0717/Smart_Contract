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
        returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

interface IStakingManager {
    function depositByPresale(address user, uint256 amount) external;
}

/// @title ProjectPresale
/// @notice Multi-stage presale supporting ETH + USDT, auto/manual advance, per-stage USD caps,
/// split-accounting across stages, staking, accurate cross-stage quoting and full analytics.
contract ProjectPresale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*──────────────────────────────
        STAGE & STATE DEFINITIONS
    ──────────────────────────────*/
    struct Stage {
        uint256 usdPerToken;     // price per token in USD × 1e18
        uint256 capTokens;       // max tokens for sale in this stage (token units)
        uint256 soldTokens;      // total tokens sold so far
        uint256 usdRaised;       // total USD raised so far
        uint256 maxUsdRaise;     // optional max USD cap (0 = none)
        uint64  startTime;
        uint64  endTime;
        bool    paused;
    }

    IERC20 public token;
    IERC20 public usdt;
    IAggregatorV3 public oracle;
    address public treasury;
    IStakingManager public stakingManager;

    uint8 public tokenDecimals;
    uint8 public usdtDecimals;
    uint256 public scale; // 10^tokenDecimals

    Stage[] private _stages;
    uint256 public currentStage;

    // global metrics
    uint256 public totalTokenSold;
    uint256 public totalUsdRaised;
    uint256 public uniqueBuyers;
    uint256 public minUsdPurchase = 50 * 1e18; // $50 minimum

    // user accounting
    mapping(address => uint256) public purchased;
    mapping(address => bool) public isBuyer;

    bool public claimEnabled;
    bool public globalPause;

    /*──────────────────────────────
                EVENTS
    ──────────────────────────────*/
    // Split-aware buy events (arrays align by index)
    event TokensBoughtSplit(
        address indexed buyer,
        address paymentToken,             // address(0) for ETH
        uint256 payAmount,                // wei or USDT units
        uint256 totalUsdSpent,            // sum of stageUsd[]
        uint256 totalTokens,              // sum of stageTokens[]
        uint256[] stageIndexes,
        uint256[] stageUsd,
        uint256[] stageTokens
    );

    event TokensBoughtAndStakedSplit(
        address indexed buyer,
        address paymentToken,             // address(0) for ETH
        uint256 payAmount,                // wei or USDT units
        uint256 totalUsdSpent,            // sum of stageUsd[]
        uint256 totalTokens,              // sum of stageTokens[]
        uint256[] stageIndexes,
        uint256[] stageUsd,
        uint256[] stageTokens
    );

    event TokensClaimed(address indexed buyer, uint256 amount);
    event TokensClaimedAndStaked(address indexed buyer, uint256 amount);
    event StageAdded(uint256 indexed id, uint256 price, uint256 cap);
    event StageUpdated(uint256 indexed id, uint256 price, uint256 cap);
    event StagePaused(uint256 indexed id, bool paused);
    event StageAdvanced(uint256 newStage);
    event StageManuallyAdvanced(uint256 fromStage, uint256 toStage);
    event ClaimEnabled(bool status);
    event TreasuryChanged(address indexed newTreasury);
    event OracleChanged(address indexed newOracle);
    event TokenChanged(address indexed newToken);
    event UsdtChanged(address indexed newUsdt);
    event StakingManagerSet(address indexed mgr);
    event MinimumPurchaseSet(uint256 newMinUsd);

    /*──────────────────────────────
            INITIALIZATION
    ──────────────────────────────*/
    constructor(
        address token_,
        address usdt_,
        address treasury_,
        address oracle_,
        Stage[] memory stages_
    ) Ownable(msg.sender) {
        require(token_ != address(0) && usdt_ != address(0) && treasury_ != address(0), "zero");
        token = IERC20(token_);
        usdt = IERC20(usdt_);
        treasury = treasury_;
        oracle = IAggregatorV3(oracle_);
        tokenDecimals = IERC20Metadata(token_).decimals();
        usdtDecimals = IERC20Metadata(usdt_).decimals();
        scale = 10 ** tokenDecimals;

        for (uint256 i; i < stages_.length; ++i) {
            require(stages_[i].usdPerToken > 0 && stages_[i].capTokens > 0, "stage");
            _stages.push(stages_[i]);
            emit StageAdded(i, stages_[i].usdPerToken, stages_[i].capTokens);
        }
    }

    /*──────────────────────────────
            ADMIN CONFIG
    ──────────────────────────────*/
    function setTreasury(address t) external onlyOwner {
        require(t != address(0), "zero");
        treasury = t;
        emit TreasuryChanged(t);
    }

    function setOracle(address o) external onlyOwner {
        require(o != address(0), "zero");
        oracle = IAggregatorV3(o);
        emit OracleChanged(o);
    }

    function setToken(address t) external onlyOwner {
        require(t != address(0), "zero");
        token = IERC20(t);
        tokenDecimals = IERC20Metadata(t).decimals();
        scale = 10 ** tokenDecimals;
        emit TokenChanged(t);
    }

    function setUsdt(address u) external onlyOwner {
        require(u != address(0), "zero");
        usdt = IERC20(u);
        usdtDecimals = IERC20Metadata(u).decimals();
        emit UsdtChanged(u);
    }

    function setStakingManager(address mgr) external onlyOwner {
        require(mgr != address(0), "zero");
        stakingManager = IStakingManager(mgr);
        IERC20(token).approve(mgr, type(uint256).max);
        emit StakingManagerSet(mgr);
    }

    function toggleClaim(bool v) external onlyOwner {
        claimEnabled = v;
        emit ClaimEnabled(v);
    }

    function setGlobalPause(bool v) external onlyOwner {
        globalPause = v;
    }

    function setMinPurchaseUsd(uint256 newMinUsd) external onlyOwner {
        require(newMinUsd > 0, "zero");
        minUsdPurchase = newMinUsd;
        emit MinimumPurchaseSet(newMinUsd);
    }

    /*──────────────────────────────
           STAGE MANAGEMENT
    ──────────────────────────────*/
    function addStage(Stage calldata s) external onlyOwner {
        require(s.usdPerToken > 0 && s.capTokens > 0, "bad");
        _stages.push(s);
        emit StageAdded(_stages.length - 1, s.usdPerToken, s.capTokens);
    }

    function updateStage(uint256 i, Stage calldata s) external onlyOwner {
        require(i < _stages.length, "range");
        _stages[i] = s;
        emit StageUpdated(i, s.usdPerToken, s.capTokens);
    }

    function pauseStage(uint256 i, bool v) external onlyOwner {
        require(i < _stages.length, "range");
        _stages[i].paused = v;
        emit StagePaused(i, v);
    }

    /// @notice Manually advance to another valid stage if operations require.
    function manualAdvance(uint256 newStage) external onlyOwner {
        require(newStage < _stages.length, "range");
        require(newStage != currentStage, "same");
        // avoid jumping forward while current stage still active and not complete
        if (newStage > currentStage) {
            Stage storage cur = _stages[currentStage];
            require(
                (cur.endTime != 0 && block.timestamp >= cur.endTime) ||
                cur.soldTokens >= cur.capTokens ||
                (cur.maxUsdRaise > 0 && cur.usdRaised >= cur.maxUsdRaise),
                "current active"
            );
        }
        emit StageManuallyAdvanced(currentStage, newStage);
        currentStage = newStage;
    }

    function stagesCount() external view returns (uint256) {
        return _stages.length;
    }

    function getStage(uint256 i) external view returns (Stage memory) {
        return _stages[i];
    }

    /*──────────────────────────────
             BUY LOGIC
    ──────────────────────────────*/
    function buyWithUsdt(uint256 usdtAmount, bool stake) external nonReentrant {
        require(!globalPause, "paused");
        require(usdtAmount > 0, "no usdt");

        uint256 usdAmount = _toUsd(usdtAmount);
        require(usdAmount >= minUsdPurchase, "below min");

        (uint256 totalTokens, uint256 usdUsed, uint256[] memory idx, uint256[] memory usdParts, uint256[] memory tokenParts)
            = _simulateAllocationUsd(usdAmount);

        // apply allocation (mutates stage state)
        _applyAllocation(idx, usdParts, tokenParts);

        // USDT goes directly to treasury (we accept full usdtAmount since usdUsed == usdAmount here)
        usdt.safeTransferFrom(msg.sender, treasury, usdtAmount);

        _finalizePurchase(msg.sender, totalTokens, usdUsed, address(usdt), usdtAmount, stake, idx, usdParts, tokenParts);
    }

    function buyWithEth(bool stake) external payable nonReentrant {
        require(!globalPause, "paused");
        require(msg.value > 0, "no eth");

        uint256 usdAmount = _ethToUsd(msg.value);
        require(usdAmount >= minUsdPurchase, "below min");

        (uint256 totalTokens, uint256 usdUsed, uint256[] memory idx, uint256[] memory usdParts, uint256[] memory tokenParts)
            = _simulateAllocationUsd(usdAmount);

        _applyAllocation(idx, usdParts, tokenParts);

        // instantly forward ETH to treasury
        (bool ok, ) = payable(treasury).call{value: msg.value}("");
        require(ok, "eth fwd fail");

        _finalizePurchase(msg.sender, totalTokens, usdUsed, address(0), msg.value, stake, idx, usdParts, tokenParts);
    }

    /*──────────────────────────────
                CLAIM
    ──────────────────────────────*/
    function claim(bool stake) external nonReentrant {
        require(claimEnabled, "claim off");
        uint256 amount = purchased[msg.sender];
        require(amount > 0, "none");
        purchased[msg.sender] = 0;

        if (stake) {
            require(address(stakingManager) != address(0), "no stake mgr");
            stakingManager.depositByPresale(msg.sender, amount);
            emit TokensClaimedAndStaked(msg.sender, amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
            emit TokensClaimed(msg.sender, amount);
        }
    }

    /*──────────────────────────────
              PUBLIC VIEWS
    ──────────────────────────────*/
    /// @notice Accurate cross-stage quote: ETH required to acquire `tokens` given current/future stages.
    function quoteEthForTokens(uint256 tokens) external view returns (uint256 ethRequired) {
        uint256 usd = _quoteUsdForTokensAcrossStages(tokens);
        ethRequired = _usdToEth(usd);
    }

    /// @notice Accurate cross-stage quote: USDT required to acquire `tokens` given current/future stages.
    function quoteUsdtForTokens(uint256 tokens) external view returns (uint256 usdtRequired) {
        uint256 usd = _quoteUsdForTokensAcrossStages(tokens);
        usdtRequired = _usdToUsdt(usd);
    }

    /// @notice Given a USD budget, returns the tokens obtainable across stages (simulation).
    function quoteTokensForUsd(uint256 usdBudget)
        external
        view
        returns (uint256 tokensOut, uint256[] memory stageIndexes, uint256[] memory stageUsd, uint256[] memory stageTokens)
    {
        (tokensOut, , stageIndexes, stageUsd, stageTokens) = _simulateAllocationUsd(usdBudget);
    }

    function getOverallStats()
        external
        view
        returns (uint256 tokensSold, uint256 usdRaised, uint256 buyers)
    {
        return (totalTokenSold, totalUsdRaised, uniqueBuyers);
    }

    /*──────────────────────────────
         ALLOCATION (SIMULATE/APPLY)
    ──────────────────────────────*/
    /// @dev Simulate allocation of a USD budget over stages (view-only). Returns arrays sized to the number of touched stages.
    function _simulateAllocationUsd(uint256 usdBudget)
        internal
        view
        returns (
            uint256 totalTokens,
            uint256 usdUsedTotal,
            uint256[] memory stageIdx,
            uint256[] memory usdParts,
            uint256[] memory tokenParts
        )
    {
        // First pass: count how many stages will be touched
        uint256 i = currentStage;
        uint256 n = _stages.length;
        uint256 remaining = usdBudget;
        uint256 touches;

        while (i < n && remaining > 0) {
            Stage memory s = _stages[i];
            if (s.paused) { ++i; continue; }
            if (s.endTime != 0 && block.timestamp > s.endTime) { ++i; continue; }
            if (s.startTime != 0 && block.timestamp < s.startTime) break;

            uint256 leftTokens = s.capTokens - s.soldTokens;
            if (leftTokens == 0) { ++i; continue; }

            uint256 stageLeftUsd = (s.maxUsdRaise > 0 && s.usdRaised < s.maxUsdRaise)
                ? (s.maxUsdRaise - s.usdRaised)
                : type(uint256).max;

            uint256 usdThisStage = remaining < stageLeftUsd ? remaining : stageLeftUsd;
            uint256 tokensThisStage = (usdThisStage * scale) / s.usdPerToken;

            if (tokensThisStage > leftTokens) {
                tokensThisStage = leftTokens;
                usdThisStage = (tokensThisStage * s.usdPerToken) / scale;
            }
            if (tokensThisStage == 0) break;

            ++touches;
            remaining -= usdThisStage;
            ++i;
        }
        require(touches > 0, "sold out");

        // Second pass: fill arrays
        stageIdx  = new uint256[](touches);
        usdParts  = new uint256[](touches);
        tokenParts= new uint256[](touches);

        i = currentStage;
        n = _stages.length;
        remaining = usdBudget;
        uint256 k;

        while (i < n && remaining > 0 && k < touches) {
            Stage memory s = _stages[i];
            if (s.paused) { ++i; continue; }
            if (s.endTime != 0 && block.timestamp > s.endTime) { ++i; continue; }
            if (s.startTime != 0 && block.timestamp < s.startTime) break;

            uint256 leftTokens = s.capTokens - s.soldTokens;
            if (leftTokens == 0) { ++i; continue; }

            uint256 stageLeftUsd = (s.maxUsdRaise > 0 && s.usdRaised < s.maxUsdRaise)
                ? (s.maxUsdRaise - s.usdRaised)
                : type(uint256).max;

            uint256 usdThisStage = remaining < stageLeftUsd ? remaining : stageLeftUsd;
            uint256 tokensThisStage = (usdThisStage * scale) / s.usdPerToken;

            if (tokensThisStage > leftTokens) {
                tokensThisStage = leftTokens;
                usdThisStage = (tokensThisStage * s.usdPerToken) / scale;
            }
            if (tokensThisStage == 0) break;

            stageIdx[k]   = i;
            usdParts[k]   = usdThisStage;
            tokenParts[k] = tokensThisStage;

            totalTokens   += tokensThisStage;
            usdUsedTotal  += usdThisStage;

            remaining -= usdThisStage;
            ++i; ++k;
        }
    }

    /// @dev Apply a previously simulated allocation (mutates storage, advances stage pointer).
    function _applyAllocation(
        uint256[] memory stageIdx,
        uint256[] memory usdParts,
        uint256[] memory tokenParts
    ) internal {
        uint256 len = stageIdx.length;
        for (uint256 k = 0; k < len; ++k) {
            uint256 i = stageIdx[k];
            Stage storage s = _stages[i];
            s.soldTokens += tokenParts[k];
            s.usdRaised  += usdParts[k];

            bool reachedCap = s.soldTokens >= s.capTokens;
            bool reachedUsd = s.maxUsdRaise > 0 && s.usdRaised >= s.maxUsdRaise;
            bool timeExpired = s.endTime > 0 && block.timestamp >= s.endTime;

            if ((reachedCap || reachedUsd || timeExpired) && i == currentStage && i + 1 < _stages.length) {
                currentStage = i + 1;
                emit StageAdvanced(currentStage);
            }
        }
    }

    function _finalizePurchase(
        address buyer,
        uint256 totalTokens,
        uint256 usdUsed,
        address payToken,
        uint256 payAmount,
        bool stake,
        uint256[] memory idx,
        uint256[] memory usdParts,
        uint256[] memory tokenParts
    ) internal {
        if (!isBuyer[buyer]) {
            isBuyer[buyer] = true;
            ++uniqueBuyers;
        }

        totalTokenSold += totalTokens;
        totalUsdRaised += usdUsed;

        if (stake) {
            require(address(stakingManager) != address(0), "no stake mgr");
            stakingManager.depositByPresale(buyer, totalTokens);
            emit TokensBoughtAndStakedSplit(
                buyer, payToken, payAmount, usdUsed, totalTokens, idx, usdParts, tokenParts
            );
        } else {
            purchased[buyer] += totalTokens;
            emit TokensBoughtSplit(
                buyer, payToken, payAmount, usdUsed, totalTokens, idx, usdParts, tokenParts
            );
        }
    }

    /*──────────────────────────────
          CROSS-STAGE QUOTING
    ──────────────────────────────*/
    /// @dev Accurate USD needed to acquire `tokensWanted` across current/future stages.
    function _quoteUsdForTokensAcrossStages(uint256 tokensWanted) internal view returns (uint256 usdTotal) {
        require(tokensWanted > 0, "zero");
        uint256 i = currentStage;
        uint256 n = _stages.length;
        uint256 remaining = tokensWanted;

        while (i < n && remaining > 0) {
            Stage memory s = _stages[i];
            if (s.paused) { ++i; continue; }
            if (s.endTime != 0 && block.timestamp > s.endTime) { ++i; continue; }
            if (s.startTime != 0 && block.timestamp < s.startTime) break;

            uint256 leftTokens = s.capTokens - s.soldTokens;
            if (leftTokens == 0) { ++i; continue; }

            // Also respect USD headroom if maxUsdRaise is set
            uint256 stageUsdHeadroom = (s.maxUsdRaise > 0 && s.usdRaised < s.maxUsdRaise)
                ? (s.maxUsdRaise - s.usdRaised)
                : type(uint256).max;

            // tokens limited by USD headroom:
            uint256 tokensByUsdHeadroom = (stageUsdHeadroom == type(uint256).max)
                ? leftTokens
                : (stageUsdHeadroom * scale) / s.usdPerToken;

            uint256 takeTokens = remaining;
            if (takeTokens > leftTokens) takeTokens = leftTokens;
            if (takeTokens > tokensByUsdHeadroom) takeTokens = tokensByUsdHeadroom;
            if (takeTokens == 0) break;

            uint256 usdThis = (takeTokens * s.usdPerToken) / scale;
            usdTotal += usdThis;
            remaining -= takeTokens;
            ++i;
        }

        require(remaining == 0, "insufficient future stages");
    }

    /*──────────────────────────────
              CONVERSIONS
    ──────────────────────────────*/
    function _ethToUsd(uint256 weiAmt) internal view returns (uint256) {
        (, int256 answer,,,) = oracle.latestRoundData();
        require(answer > 0, "oracle");
        uint8 d = oracle.decimals();
        uint256 price = uint256(answer);
        if (d >= 18) return (weiAmt * price) / (10 ** d);
        uint256 scaled = price * (10 ** (18 - d));
        return (weiAmt * scaled) / 1e18;
    }

    function _usdToEth(uint256 usdAmount) internal view returns (uint256) {
        (, int256 answer,,,) = oracle.latestRoundData();
        require(answer > 0, "oracle");
        uint8 d = oracle.decimals();
        uint256 price = uint256(answer);
        if (d >= 18) return (usdAmount * (10 ** d)) / price;
        uint256 scaled = price * (10 ** (18 - d));
        return (usdAmount * 1e18) / scaled;
    }

    function _toUsd(uint256 usdtAmt) internal view returns (uint256) {
        if (usdtDecimals < 18) return usdtAmt * (10 ** (18 - usdtDecimals));
        return usdtAmt;
    }

    function _usdToUsdt(uint256 usdAmount) internal view returns (uint256) {
        if (usdtDecimals < 18) return usdAmount / (10 ** (18 - usdtDecimals));
        return usdAmount;
    }

    function _usdOfTokens(uint256 tokens, uint256 usdPerToken)
        internal
        view
        returns (uint256)
    {
        return (tokens * usdPerToken) / scale;
    }

    /*──────────────────────────────
              RESCUE / SAFETY
    ──────────────────────────────*/
    function rescueERC20(address erc20, uint256 amount) external onlyOwner {
        IERC20(erc20).safeTransfer(treasury, amount);
    }

    // No idle ETH: any direct transfer reverts.
    receive() external payable {
        revert("Direct ETH not accepted");
    }
}
