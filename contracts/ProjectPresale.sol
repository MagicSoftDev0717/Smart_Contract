// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {
    IERC20,
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
        uint256 usdPerToken; // price per token in USD × 1e18
        uint256 capTokens; // max tokens for sale in this stage (token units)
        uint256 soldTokens; // total tokens sold so far
        uint256 usdRaised; // total USD raised so far
        uint256 maxUsdRaise; // optional max USD cap (0 = none)
        uint64 startTime;
        uint64 endTime;
        bool paused;
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
    uint256 public minUsdPurchase = 25 * 1e18; // $50 minimum

    // user accounting
    // mapping(address => uint256) public purchased;
    // mapping(address => bool) public isBuyer;

    // after
    mapping(address => uint256) private purchased;
    mapping(address => bool) private isBuyer;

    bool public claimEnabled;
    bool public globalPause;

    ///////////////////////////
    // Modes for event verbosity
    enum EventsMode {
        Detailed,
        Compact,
        Minimal
    }
    EventsMode public eventsMode;

    event EventsModeChanged(EventsMode mode);

    function setEventsMode(EventsMode mode) external onlyOwner {
        eventsMode = mode;
        emit EventsModeChanged(mode);
    }

    /*──────────────────────────────
                EVENTS
    ──────────────────────────────*/
    // Split-aware buy events (arrays align by index)
    event TokensBoughtSplit(
        address indexed buyer,
        address paymentToken, // address(0) for ETH
        uint256 payAmount, // wei or USDT units
        uint256 totalUsdSpent, // sum of stageUsd[]
        uint256 totalTokens, // sum of stageTokens[]
        uint256[] stageIndexes,
        uint256[] stageUsd,
        uint256[] stageTokens
    );

    event TokensBoughtAndStakedSplit(
        address indexed buyer,
        address paymentToken, // address(0) for ETH
        uint256 payAmount, // wei or USDT units
        uint256 totalUsdSpent, // sum of stageUsd[]
        uint256 totalTokens, // sum of stageTokens[]
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

    /////////////--New Add for M2--//////////
    event StageEarlyEnded(
        uint256 indexed stageId,
        uint256 rolloverTokens,
        uint256 newCurrentStage
    );
    event StageCanceled(
        uint256 indexed stageId,
        uint256 rolloverTokens,
        uint256 newCurrentStage
    );
    event StageAddedSimple(
        uint256 indexed id,
        uint256 price,
        uint256 cap,
        uint256 maxUsdRaise,
        bool paused
    );
    event UnsoldTokensRescued(uint256 amount);

    // Add compact events (no arrays)
    event TokensBought(
        address indexed buyer,
        address paymentToken, // address(0) for ETH
        uint256 payAmount, // wei or USDT units
        uint256 totalUsdSpent,
        uint256 totalTokens
    );

    event TokensBoughtAndStaked(
        address indexed buyer,
        address paymentToken,
        uint256 payAmount,
        uint256 totalUsdSpent,
        uint256 totalTokens
    );

    error ZeroAddress();
    error Range(uint256 i);
    error SoldOut();
    error Same();
    error Paused();
    error BelowMin();
    error NoStakeManager();
    error ClaimOff();
    error BadStage(); // usdPerToken==0 or capTokens==0
    error NoStage();
    error NothingToEnd();
    error Corrupt();
    error NoUSDT();
    error None();
    error Zero();
    error InsufficientFutureStages();
    error Oracle();
    error DebugDisabled();

    function getMyClaimable() external view returns (uint256) {
        return purchased[msg.sender];
    }

    function getMySummary()
        external
        view
        returns (
            uint256 claimable,
            bool hasPurchased,
            uint256 totalSold,
            uint256 totalUsd
        )
    {
        claimable = purchased[msg.sender];
        hasPurchased = isBuyer[msg.sender];
        totalSold = totalTokenSold;
        totalUsd = totalUsdRaised;
    }

    // Optional support view for customer service / ops
    function getUserSummary(
        address user
    ) external view onlyOwner returns (uint256 claimable, bool hasPurchased) {
        claimable = purchased[user];
        hasPurchased = isBuyer[user];
    }

    /////One-way “fuse” (owner can disable forever)/////
    error DebugLocked();

    bool public debugViewsEnabled; // default true on testnet, false on mainnet (your choice)
    bool public debugViewsLocked; // when true, cannot re-enable

    event DebugViewsToggled(bool enabled);
    event DebugViewsLocked();

    function setDebugViews(bool v) external onlyOwner {
        if (debugViewsLocked) revert DebugLocked();
        // idempotent shortcut
        if (debugViewsEnabled == v) return;
        debugViewsEnabled = v;
        emit DebugViewsToggled(v);
    }

    // irreversible: turns OFF and locks
    function lockDebugViews() external onlyOwner {
        if (debugViewsLocked) return;
        debugViewsEnabled = false;
        debugViewsLocked = true;
        emit DebugViewsLocked();
    }

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
        // require(
        //     token_ != address(0) &&
        //         usdt_ != address(0) &&
        //         treasury_ != address(0),
        //     "zero"
        // );
        if (
            treasury_ == address(0) &&
            token_ == address(0) &&
            usdt_ == address(0)
        ) revert ZeroAddress();

        token = IERC20(token_);
        usdt = IERC20(usdt_);
        treasury = treasury_;
        oracle = IAggregatorV3(oracle_);
        tokenDecimals = IERC20Metadata(token_).decimals();
        usdtDecimals = IERC20Metadata(usdt_).decimals();
        scale = 10 ** tokenDecimals;

        for (uint256 i; i < stages_.length; ++i) {
            require(
                stages_[i].usdPerToken > 0 && stages_[i].capTokens > 0,
                "stage"
            );
            _stages.push(stages_[i]);
            emit StageAdded(i, stages_[i].usdPerToken, stages_[i].capTokens);
        }
    }

    /*──────────────────────────────
            ADMIN CONFIG
    ──────────────────────────────*/
    function setTreasury(address t) external onlyOwner {
        // require(t != address(0), "zero");
        if (t == address(0)) revert ZeroAddress();
        treasury = t;
        emit TreasuryChanged(t);
    }

    function setOracle(address o) external onlyOwner {
        // require(o != address(0), "zero");
        if (o == address(0)) revert ZeroAddress();
        if (o == address(oracle)) return;
        oracle = IAggregatorV3(o);
        emit OracleChanged(o);
    }

    function setToken(address t) external onlyOwner {
        // require(t != address(0), "zero");
        if (t == address(0)) revert ZeroAddress();
        if (t == address(token)) return;
        token = IERC20(t);
        tokenDecimals = IERC20Metadata(t).decimals();
        scale = 10 ** tokenDecimals;
        emit TokenChanged(t);
    }

    function setUsdt(address u) external onlyOwner {
        // require(u != address(0), "zero");
        if (u == address(0)) revert ZeroAddress();
        if (u == address(usdt)) return;
        usdt = IERC20(u);
        usdtDecimals = IERC20Metadata(u).decimals();
        emit UsdtChanged(u);
    }

    function setStakingManager(address mgr) external onlyOwner {
        // require(mgr != address(0), "zero");
        if (mgr == address(0)) revert ZeroAddress();
        if (mgr == address(stakingManager)) return;
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
        // require(s.usdPerToken > 0 && s.capTokens > 0, "bad");
        if (s.usdPerToken == 0 || s.capTokens == 0) revert BadStage();
        _stages.push(s);
        emit StageAdded(_stages.length - 1, s.usdPerToken, s.capTokens);
    }
    /////--Add new for M2--///////////
    function addStageSimple(
        uint256 usdPerToken,
        uint256 capTokens,
        uint256 maxUsdRaise,
        bool paused
    ) external onlyOwner {
        // require(usdPerToken > 0 && capTokens > 0, "bad");
        if (usdPerToken == 0 || capTokens == 0) revert BadStage();
        Stage memory s = Stage({
            usdPerToken: usdPerToken,
            capTokens: capTokens,
            soldTokens: 0,
            usdRaised: 0,
            maxUsdRaise: maxUsdRaise,
            startTime: 0, // ignored if you’re running quantity-only stages
            endTime: 0, // ignored
            paused: paused
        });
        _stages.push(s);
        emit StageAddedSimple(
            _stages.length - 1,
            usdPerToken,
            capTokens,
            maxUsdRaise,
            paused
        );
    }
    ////////////////////////////////////////////
    function updateStage(uint256 i, Stage calldata s) external onlyOwner {
        // require(i < _stages.length, "range");
        if (i >= _stages.length) revert Range(i);
        _stages[i] = s;
        emit StageUpdated(i, s.usdPerToken, s.capTokens);
    }

    function pauseStage(uint256 i, bool v) external onlyOwner {
        // require(i < _stages.length, "range");
        if (i >= _stages.length) revert Range(i);
        _stages[i].paused = v;
        emit StagePaused(i, v);
    }

    /// @notice Manually advance to another valid stage if operations require.
    function manualAdvance(uint256 newStage) external onlyOwner {
        // require(newStage < _stages.length, "range");
        // require(newStage != currentStage, "same");
        uint256 cur = currentStage;
        if (newStage >= _stages.length) revert Range(newStage);
        if (newStage == cur) revert Same();
        // avoid jumping forward while current stage still active and not complete
        if (newStage > currentStage) {
            Stage storage s = _stages[cur];
            // require(
            //     (cur.endTime != 0 && block.timestamp >= cur.endTime) ||
            //         cur.soldTokens >= cur.capTokens ||
            //         (cur.maxUsdRaise > 0 && cur.usdRaised >= cur.maxUsdRaise),
            //     "current active"
            // );
            bool reachedCap = s.soldTokens >= s.capTokens;
            bool reachedUsd = (s.maxUsdRaise > 0 &&
                s.usdRaised >= s.maxUsdRaise);
            if (!reachedCap && !reachedUsd) revert BadStage(); // “current still active”
        }
        emit StageManuallyAdvanced(currentStage, newStage);
        currentStage = newStage;
    }

    function stagesCount() external view returns (uint256) {
        if (!debugViewsEnabled) revert DebugDisabled();
        return _stages.length;
    }

    function getStage(uint256 i) external view returns (Stage memory) {
        if (!debugViewsEnabled) revert DebugDisabled();
        if (i >= _stages.length) revert Range(i);
        return _stages[i];
    }

    ///////////--New Add for M2--//////////

    function earlyEndAndRollover() external onlyOwner {
        uint256 i = currentStage;
        // require(i < _stages.length, "no stage");
        if (i >= _stages.length) revert NoStage();
        Stage storage cur = _stages[i];
        // require(!cur.paused, "paused");
        if (cur.paused) revert Paused();

        uint256 sold = cur.soldTokens;
        uint256 cap = cur.capTokens;
        // require(sold < cap, "nothing to end");
        if (sold >= cap) revert NothingToEnd();

        uint256 rollover = cap - sold;

        // Lock current stage at sold = cap to mark complete
        cur.capTokens = sold;

        if (i + 1 < _stages.length) {
            // move remaining capacity to next stage
            _stages[i + 1].capTokens += rollover;
            currentStage = i + 1;
            emit StageEarlyEnded(i, rollover, currentStage);
            emit StageAdvanced(currentStage);
        } else {
            // last stage: keep cap reduced; no next stage to rollover into
            emit StageEarlyEnded(i, 0, currentStage);
        }
    }

    function cancelCurrentStageAndContinue() external onlyOwner {
        uint256 i = currentStage;
        // require(i < _stages.length, "no stage");
        if (i >= _stages.length) revert NoStage();

        Stage storage cur = _stages[i];

        uint256 sold = cur.soldTokens;
        uint256 cap = cur.capTokens;
        // require(sold <= cap, "corrupt");
        if (sold > cap) revert Corrupt();

        uint256 rollover = cap > sold ? (cap - sold) : 0;

        // Lock current stage at sold
        cur.capTokens = sold;
        cur.paused = true;

        if (i + 1 < _stages.length) {
            _stages[i + 1].capTokens += rollover;
            currentStage = i + 1;
            emit StageCanceled(i, rollover, currentStage);
            emit StageAdvanced(currentStage);
        } else {
            // last stage; just mark canceled/closed (no rollover target)
            emit StageCanceled(i, 0, currentStage);
        }
    }
    /////////////////////////////////////////////////
    /*──────────────────────────────
             BUY LOGIC
    ──────────────────────────────*/
    function buyWithUsdt(uint256 usdtAmount, bool stake) external nonReentrant {
        // require(!globalPause, "paused");
        if (globalPause) revert Paused();
        // require(usdtAmount > 0, "no usdt");
        if (usdtAmount == 0) revert NoUSDT();

        ////---Modify for gas save for M2--////
        // Cache storage variables in memory for this call
        IERC20 _usdt = usdt;
        address _treasury = treasury;
        ///////////////////////////////////

        uint256 usdAmount = _toUsd(usdtAmount);
        // require(usdAmount >= minUsdPurchase, "below min");
        if (usdAmount < minUsdPurchase) revert BelowMin();
        (
            uint256 totalTokens,
            uint256 usdUsed,
            uint256[] memory idx,
            uint256[] memory usdParts,
            uint256[] memory tokenParts
        ) = _simulateAllocationUsd(usdAmount);

        // apply allocation (mutates stage state)
        _applyAllocation(idx, usdParts, tokenParts);

        // USDT goes directly to treasury (we accept full usdtAmount since usdUsed == usdAmount here)
        // usdt.safeTransferFrom(msg.sender, treasury, usdtAmount);
        //////////---Modify for gas save for M2--//////////
        _usdt.safeTransferFrom(msg.sender, _treasury, usdtAmount);

        _finalizePurchase(
            msg.sender,
            totalTokens,
            usdUsed,
            // address(usdt),
            ////---Modify for gas save for M2--////
            address(_usdt),
            usdtAmount,
            stake,
            idx,
            usdParts,
            tokenParts
        );
    }

    function buyWithEth(bool stake) external payable nonReentrant {
        // require(!globalPause, "paused");
        if (globalPause) revert Paused();
        // require(msg.value > 0, "no eth");
        if (msg.value == 0) revert BelowMin();

        uint256 usdAmount = _ethToUsd(msg.value);
        // require(usdAmount >= minUsdPurchase, "below min");
        if (usdAmount < minUsdPurchase) revert BelowMin();
        (
            uint256 totalTokens,
            uint256 usdUsed,
            uint256[] memory idx,
            uint256[] memory usdParts,
            uint256[] memory tokenParts
        ) = _simulateAllocationUsd(usdAmount);

        _applyAllocation(idx, usdParts, tokenParts);

        //  Cache storage variables
        address _treasury = treasury;

        // instantly forward ETH to treasury
        // (bool ok, ) = payable(treasury).call{value: msg.value}("");
        ////---Modify for gas save for M2--////
        (bool ok, ) = payable(_treasury).call{value: msg.value}("");
        // require(ok, "eth fwd fail");

        //----Modify for witching to custom errors for M2--////
        if (!ok) revert(); // minimal; or define a custom error

        _finalizePurchase(
            msg.sender,
            totalTokens,
            usdUsed,
            address(0),
            msg.value,
            stake,
            idx,
            usdParts,
            tokenParts
        );
    }

    /*──────────────────────────────
                CLAIM
    ──────────────────────────────*/
    function claim(bool stake) external nonReentrant {
        // require(claimEnabled, "claim off");
        if (!claimEnabled) revert ClaimOff();
        uint256 amount = purchased[msg.sender];
        // require(amount > 0, "none");
        if (amount == 0) revert None();

        purchased[msg.sender] = 0;

        if (stake) {
            // require(address(stakingManager) != address(0), "no stake mgr");
            if (address(stakingManager) == address(0)) revert NoStakeManager();
            stakingManager.depositByPresale(msg.sender, amount);
            emit TokensClaimedAndStaked(msg.sender, amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
            emit TokensClaimed(msg.sender, amount);
        }
    }

    /*──────────────────────────────
              Pulic VIEWS
    ──────────────────────────────*/
    /// @notice Accurate cross-stage quote: ETH required to acquire `tokens` given current/future stages.
    function quoteEthForTokens(
        uint256 tokens
    ) external view returns (uint256 ethRequired) {
        uint256 usd = _quoteUsdForTokensAcrossStages(tokens);
        ethRequired = _usdToEth(usd);
    }

    /// @notice Accurate cross-stage quote: USDT required to acquire `tokens` given current/future stages.
    function quoteUsdtForTokens(
        uint256 tokens
    ) external view returns (uint256 usdtRequired) {
        uint256 usd = _quoteUsdForTokensAcrossStages(tokens);
        usdtRequired = _usdToUsdt(usd);
    }

    /// @notice Given a USD budget, returns the tokens obtainable across stages (simulation).
    function quoteTokensForUsd(
        uint256 usdBudget
    )
        external
        view
        returns (
            uint256 tokensOut,
            uint256[] memory stageIndexes,
            uint256[] memory stageUsd,
            uint256[] memory stageTokens
        )
    {
        (
            tokensOut,
            ,
            stageIndexes,
            stageUsd,
            stageTokens
        ) = _simulateAllocationUsd(usdBudget);
    }

    function getOverallStats()
        external
        view
        returns (uint256 tokensSold, uint256 usdRaised, uint256 buyers)
    {
        return (totalTokenSold, totalUsdRaised, uniqueBuyers);
    }

    //////////////////////
    function getActiveWindow()
        external
        view
        returns (
            uint256 _current,
            Stage memory _curStage,
            uint256 _nextIndex,
            Stage memory _nextStage
        )
    {
        uint256 cur = currentStage;
        _current = cur;
        _curStage = _stages[cur];
        uint256 nxt = cur + 1;
        if (nxt < _stages.length) {
            _nextIndex = nxt;
            _nextStage = _stages[nxt];
        }
    }

    //////

    /*──────────────────────────────
         ALLOCATION (SIMULATE/APPLY)
    ──────────────────────────────*/
    /// @dev Simulate allocation of a USD budget over stages (view-only). Returns arrays sized to the number of touched stages.
    function _simulateAllocationUsd(
        uint256 usdBudget
    )
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
        Stage[] storage stages = _stages; // micro: cache the array base
        uint256 n = _stages.length;
        uint256 remaining = usdBudget;
        //--add new for gas save for 2 --////
        uint256 _scale = scale; // cache once

        // Upper-bound arrays (n). We'll fill [0..touches) and then shrink by copying.
        // uint256[] memory stageIdxTmp = new uint256[](n);
        // uint256[] memory usdPartsTmp = new uint256[](n);
        // uint256[] memory tokenPartsTmp = new uint256[](n);

        // Pre-allocate at upper bound; we’ll truncate at the end.
        stageIdx = new uint256[](n);
        usdParts = new uint256[](n);
        tokenParts = new uint256[](n);
        uint256 touches;

        while (i < n && remaining > 0) {
            // STORAGE ref for the stage
            Stage storage s = stages[i];

            // Cache only the fields we need into stack locals (one SLOAD per field)
            bool paused = s.paused;
            uint256 sold = s.soldTokens;
            uint256 cap = s.capTokens;

            if (paused) {
                // ++i;
                unchecked {
                    ++i;
                }
                continue;
            }

            uint256 leftTokens = cap - sold;
            /////////--Add new remove for M2--//////////
            // if (s.endTime != 0 && block.timestamp > s.endTime) {
            //     ++i;
            //     continue;
            // }
            // if (s.startTime != 0 && block.timestamp < s.startTime) break;

            // uint256 leftTokens = s.capTokens - s.soldTokens;
            // if (leftTokens == 0) {
            //     // ++i;
            //     unchecked {
            //         ++i;
            //     }
            //     continue;
            // }

            uint256 maxUsd = s.maxUsdRaise;
            uint256 raised = s.usdRaised;

            uint256 stageLeftUsd = (maxUsd > 0 && raised < maxUsd)
                ? (maxUsd - raised)
                : type(uint256).max;

            if (stageLeftUsd == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            uint256 price = s.usdPerToken; // cache price once
            uint256 usdThisStage = remaining < stageLeftUsd
                ? remaining
                : stageLeftUsd;
            uint256 tokensThisStage = (usdThisStage * _scale) / price;
            // uint256 tokensThisStage = _tokensFromUsd(
            //     usdThisStage,
            //     price,
            //     _scale
            // );

            if (tokensThisStage > leftTokens) {
                tokensThisStage = leftTokens;
                usdThisStage = (tokensThisStage * price) / _scale;
            }
            if (tokensThisStage == 0) break;

            // Write directly into the temp arrays at index = touches
            // stageIdxTmp[touches] = i;
            // usdPartsTmp[touches] = usdThisStage;
            // tokenPartsTmp[touches] = tokensThisStage;

            // Write into prefix slot
            stageIdx[touches] = i;
            usdParts[touches] = usdThisStage;
            tokenParts[touches] = tokensThisStage;

            totalTokens += tokensThisStage;
            usdUsedTotal += usdThisStage;

            // ++touches;
            remaining -= usdThisStage;
            // ++i;
            unchecked {
                ++touches;
                ++i;
            }
        }
        // require(touches > 0, "sold out");
        if (touches == 0) revert SoldOut(); // "sold out"
        // Second pass: fill arrays
        // stageIdx = new uint256[](touches);
        // usdParts = new uint256[](touches);
        // tokenParts = new uint256[](touches);

        // for (uint256 k; k < touches; ) {
        //     stageIdx[k] = stageIdxTmp[k];
        //     usdParts[k] = usdPartsTmp[k];
        //     tokenParts[k] = tokenPartsTmp[k];
        //     unchecked {
        //         ++k;
        //     }
        // }

        // In-place truncate to 'touches' (no copy)
        assembly {
            mstore(stageIdx, touches)
            mstore(usdParts, touches)
            mstore(tokenParts, touches)
        }

        // i = currentStage;
        // n = _stages.length;
        // remaining = usdBudget;
        // uint256 k;

        // while (i < n && remaining > 0 && k < touches) {
        //     Stage memory s = _stages[i];
        //     if (s.paused) {
        //         ++i;
        //         continue;
        //     }
        //     /////////--Add new remove for M2--//////////
        //     // if (s.endTime != 0 && block.timestamp > s.endTime) {
        //     //     ++i;
        //     //     continue;
        //     // }
        //     // if (s.startTime != 0 && block.timestamp < s.startTime) break;

        //     uint256 leftTokens = s.capTokens - s.soldTokens;
        //     if (leftTokens == 0) {
        //         ++i;
        //         continue;
        //     }

        //     uint256 stageLeftUsd = (s.maxUsdRaise > 0 &&
        //         s.usdRaised < s.maxUsdRaise)
        //         ? (s.maxUsdRaise - s.usdRaised)
        //         : type(uint256).max;

        //     uint256 usdThisStage = remaining < stageLeftUsd
        //         ? remaining
        //         : stageLeftUsd;
        //     uint256 tokensThisStage = (usdThisStage * scale) / s.usdPerToken;

        //     if (tokensThisStage > leftTokens) {
        //         tokensThisStage = leftTokens;
        //         usdThisStage = (tokensThisStage * s.usdPerToken) / scale;
        //     }
        //     if (tokensThisStage == 0) break;

        //     stageIdx[k] = i;
        //     usdParts[k] = usdThisStage;
        //     tokenParts[k] = tokensThisStage;

        //     totalTokens += tokensThisStage;
        //     usdUsedTotal += usdThisStage;

        //     remaining -= usdThisStage;
        //     // ++i;
        //     // ++k;
        //     ////--Add new for gas save--////
        //     unchecked {
        //         ++i;
        //         ++k;
        //     } // ✅ saves gas
        // }
    }

    /// @dev Apply a previously simulated allocation (mutates storage, advances stage pointer).
    function _applyAllocation(
        uint256[] memory stageIdx,
        uint256[] memory usdParts,
        uint256[] memory tokenParts
    ) internal {
        uint256 len = stageIdx.length;
        // for (uint256 k = 0; k < len; ++k) {
        for (uint256 k = 0; k < len; ) {
            uint256 i = stageIdx[k];
            Stage storage s = _stages[i];

            s.soldTokens += tokenParts[k];
            s.usdRaised += usdParts[k];

            bool reachedCap = s.soldTokens >= s.capTokens;
            bool reachedUsd = s.maxUsdRaise > 0 && s.usdRaised >= s.maxUsdRaise;
            // bool timeExpired = s.endTime > 0 && block.timestamp >= s.endTime;
            // bool timeExpired = false;
            if (
                // (reachedCap || reachedUsd || timeExpired) &&
                // (reachedCap || reachedUsd) && i == currentStage && i + 1 < _stages.length) {
                (reachedCap || reachedUsd) && i == currentStage
            ) {
                // currentStage = i + 1;
                // emit StageAdvanced(currentStage);
                uint256 next = i + 1;
                if (next < _stages.length) {
                    currentStage = next;
                    emit StageAdvanced(next);
                }
            }
            //--Modify for without time gating + unchecked increments for M2--////
            unchecked {
                ++k;
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
            // require(address(stakingManager) != address(0), "no stake mgr");
            if (address(stakingManager) == address(0)) revert NoStakeManager();
            stakingManager.depositByPresale(buyer, totalTokens);

            //     emit TokensBoughtAndStakedSplit(
            //         buyer,
            //         payToken,
            //         payAmount,
            //         usdUsed,
            //         totalTokens,
            //         idx,
            //         usdParts,
            //         tokenParts
            //     );
            // } else {
            //     purchased[buyer] += totalTokens;
            //     emit TokensBoughtSplit(
            //         buyer,
            //         payToken,
            //         payAmount,
            //         usdUsed,
            //         totalTokens,
            //         idx,
            //         usdParts,
            //         tokenParts
            //     );
            // }

            // Verbosity switch
            EventsMode m = eventsMode;
            if (m == EventsMode.Detailed) {
                emit TokensBoughtAndStakedSplit(
                    buyer,
                    payToken,
                    payAmount,
                    usdUsed,
                    totalTokens,
                    idx,
                    usdParts,
                    tokenParts
                );
            } else if (m == EventsMode.Compact) {
                emit TokensBoughtAndStaked(
                    buyer,
                    payToken,
                    payAmount,
                    usdUsed,
                    totalTokens
                );
            } else {
                // Minimal: emit nothing (or a tiny anonymous heartbeat if you prefer)
            }
        } else {
            purchased[buyer] += totalTokens;

            EventsMode m = eventsMode;
            if (m == EventsMode.Detailed) {
                emit TokensBoughtSplit(
                    buyer,
                    payToken,
                    payAmount,
                    usdUsed,
                    totalTokens,
                    idx,
                    usdParts,
                    tokenParts
                );
            } else if (m == EventsMode.Compact) {
                emit TokensBought(
                    buyer,
                    payToken,
                    payAmount,
                    usdUsed,
                    totalTokens
                );
            } else {
                // Minimal: no event
            }
        }
    }

    /*──────────────────────────────
          CROSS-STAGE QUOTING
    ──────────────────────────────*/
    /// @dev Accurate USD needed to acquire `tokensWanted` across current/future stages.
    function _quoteUsdForTokensAcrossStages(
        uint256 tokensWanted
    ) internal view returns (uint256 usdTotal) {
        // require(tokensWanted > 0, "zero");
        if (tokensWanted == 0) revert Zero();

        uint256 i = currentStage;
        uint256 n = _stages.length;
        uint256 remaining = tokensWanted;
        uint256 _scale = scale; // cache once

        while (i < n && remaining > 0) {
            Stage memory s = _stages[i];
            if (s.paused) {
                ++i;
                continue;
            }
            /////////--Add new remove for M2--//////////
            // if (s.endTime != 0 && block.timestamp > s.endTime) {
            //     ++i;
            //     continue;
            // }
            // if (s.startTime != 0 && block.timestamp < s.startTime) break;

            uint256 leftTokens = s.capTokens - s.soldTokens;
            if (leftTokens == 0) {
                ++i;
                continue;
            }

            // Also respect USD headroom if maxUsdRaise is set
            uint256 stageUsdHeadroom = (s.maxUsdRaise > 0 &&
                s.usdRaised < s.maxUsdRaise)
                ? (s.maxUsdRaise - s.usdRaised)
                : type(uint256).max;

            // tokens limited by USD headroom:
            uint256 tokensByUsdHeadroom = (stageUsdHeadroom ==
                type(uint256).max)
                ? leftTokens
                : (stageUsdHeadroom * _scale) / s.usdPerToken;

            uint256 takeTokens = remaining;
            if (takeTokens > leftTokens) takeTokens = leftTokens;
            if (takeTokens > tokensByUsdHeadroom)
                takeTokens = tokensByUsdHeadroom;
            if (takeTokens == 0) break;

            uint256 usdThis = (takeTokens * s.usdPerToken) / _scale;
            usdTotal += usdThis;
            remaining -= takeTokens;
            // ++i;
            unchecked {
                ++i;
            }
        }

        // require(remaining == 0, "insufficient future stages");
        if (remaining != 0) revert InsufficientFutureStages();
    }

    /*──────────────────────────────
              CONVERSIONS
    ──────────────────────────────*/
    function _ethToUsd(uint256 weiAmt) internal view returns (uint256) {
        (, int256 answer, , , ) = oracle.latestRoundData();
        // require(answer > 0, "oracle");
        if (answer == 0) revert Oracle();
        uint8 d = oracle.decimals();
        uint256 price = uint256(answer);
        if (d >= 18) return (weiAmt * price) / (10 ** d);
        uint256 scaled = price * (10 ** (18 - d));
        return (weiAmt * scaled) / 1e18;
    }

    function _usdToEth(uint256 usdAmount) internal view returns (uint256) {
        (, int256 answer, , , ) = oracle.latestRoundData();
        // require(answer > 0, "oracle");
        if (answer == 0) revert Oracle();
        uint8 d = oracle.decimals();
        uint256 price = uint256(answer);
        if (d >= 18) return (usdAmount * (10 ** d)) / price;
        uint256 scaled = price * (10 ** (18 - d));
        return (usdAmount * 1e18) / scaled;
    }

    function _toUsd(uint256 usdtAmt) internal view returns (uint256) {
        // if (usdtDecimals < 18) return usdtAmt * (10 ** (18 - usdtDecimals));
        // return usdtAmt;

        ///////---Modify for gas micro-optimizations save for M2--//////////
        uint8 d = usdtDecimals; // ✅ cache in memory once

        if (d < 18) return usdtAmt * (10 ** (18 - d));
        return usdtAmt;
    }

    function _usdToUsdt(uint256 usdAmount) internal view returns (uint256) {
        // if (usdtDecimals < 18) return usdAmount / (10 ** (18 - usdtDecimals));
        // return usdAmount;

        ///-----Modify for gas micro-optimizations save for M2--//////////
        uint8 d = usdtDecimals; // ✅ cache storage value in memory once

        if (d < 18) return usdAmount / (10 ** (18 - d));
        return usdAmount;
    }

    function _usdOfTokens(
        uint256 tokens,
        uint256 usdPerToken
    ) internal view returns (uint256) {
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
    //////////-- New Add for M2--//////////
    function rescueUnsoldToTreasury(uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(treasury, amount);
        emit UnsoldTokensRescued(amount);
    }

    ////////////////
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _usdFromTokens(
        uint256 tokens,
        uint256 usdPerToken,
        uint256 _scale
    ) internal pure returns (uint256) {
        // floor division (as you already do)
        return (tokens * usdPerToken) / _scale;
    }

    function _tokensFromUsd(
        uint256 usd,
        uint256 usdPerToken,
        uint256 _scale
    ) internal pure returns (uint256) {
        return (usd * _scale) / usdPerToken;
    }
}
