// scripts/checkStages.js
const { ethers } = require("hardhat");
const { PRESALE_ADDR } = require("./constants");

const fmt = (n, d = 18) => {
  try { return ethers.formatUnits(n ?? 0n, d); } catch { return (n ?? 0n).toString(); }
};
const tsNow = () => Math.floor(Date.now() / 1000);
const dt = (t) => (Number(t) ? new Date(Number(t) * 1000).toISOString() : "0");

function stageState(s) {
  const now = tsNow();
  const start = Number(s.startTime || 0);
  const end = Number(s.endTime || 0);
  const notStarted = start > 0 && now < start;
  const expired = end > 0 && now >= end;
  const soldOut = s.capTokens > 0n && s.soldTokens >= s.capTokens;
  const usdCapped = s.maxUsdRaise > 0n && s.usdRaised >= s.maxUsdRaise;
  const active = !s.paused && !notStarted && !expired && !soldOut && !usdCapped;
  const label =
    s.paused ? "PAUSED" :
    notStarted ? "NOT_STARTED" :
    expired ? "EXPIRED" :
    soldOut ? "SOLD_OUT" :
    usdCapped ? "USD_CAPPED" :
    active ? "ACTIVE" : "INACTIVE";
  return { label, start, end, notStarted, expired, soldOut, usdCapped, active };
}

async function main() {
  console.log("\n=== Presale Stages Overview ===");

  if (!PRESALE_ADDR) {
    console.error("❌ PRESALE_ADDR not set in constants.js / .env");
    process.exit(1);
  }

  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR);

  try {
    const count = Number(await presale.stagesCount());
    const current = Number(await presale.currentStage());
    const claimEnabled = await presale.claimEnabled();
    const globalPause = await presale.globalPause?.().catch(() => false);

    console.log(` Presale:      ${PRESALE_ADDR}`);
    console.log(` Now (unix):   ${tsNow()}`);
    console.log(` currentStage: ${current}/${Math.max(count - 1, 0)}`);
    console.log(` Global pause: ${globalPause ? "ON" : "OFF"}`);
    console.log(` Claim:        ${claimEnabled ? "ENABLED" : "DISABLED"}`);
    console.log(` stagesCount:  ${count}`);

    console.log("\n== Per-stage details ==");
    let aggTokens = 0n, aggUsd = 0n;

    for (let i = 0; i < count; i++) {
      const s = await presale.getStage(i);
      const st = stageState(s);
      const isCurrent = i === current ? " (current)" : "";

      console.log(
        `#${i}${isCurrent} [${st.label}]` +
        `\n   time:     [${s.startTime} (${dt(s.startTime)}) → ${s.endTime} (${dt(s.endTime)})]` +
        `\n   price:    $${fmt(s.usdPerToken, 18)} per token (USD × 1e18)` +
        `\n   tokens:   sold=${fmt(s.soldTokens)} / cap=${fmt(s.capTokens)}` +
        `\n   USD:      raised=${fmt(s.usdRaised)} / max=${s.maxUsdRaise > 0n ? fmt(s.maxUsdRaise) : "∞"}` +
        `\n   paused:   ${s.paused}\n`
      );

      aggTokens += s.soldTokens;
      aggUsd += s.usdRaised;
    }

    const [totalSold, totalUsd, buyers] = await presale.getOverallStats();
    console.log("== Totals ==");
    console.log(`Total tokens sold: ${fmt(totalSold)}`);
    console.log(`Total USD raised:  ${fmt(totalUsd)}`);
    console.log(`Unique buyers:     ${buyers.toString()}`);

    console.log("\n== Assertions ==");
    const okTokens = aggTokens === totalSold;
    const okUsd = aggUsd === totalUsd;
    console.log(`Σ(soldTokens by stage) == totalTokenSold: ${okTokens ? "✅" : "❌"}`);
    console.log(`Σ(usdRaised by stage)  == totalUsdRaised: ${okUsd ? "✅" : "❌"}`);
    if (!okTokens || !okUsd) {
      console.warn("⚠️ Mismatch detected. Re-check recent txs, stage boundaries, or updates.");
    }
  } catch (err) {
    console.error("\n❌ Failed to read stage data.");
    if (err.shortMessage?.includes("execution reverted")) {
      console.error("   → Contract call reverted (check address or network).");
    } else if (err.code === "NETWORK_ERROR") {
      console.error("   → Network/RPC issue. Verify --network and your RPC URL.");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
    process.exit(1);
  }
}

main().catch(console.error);
