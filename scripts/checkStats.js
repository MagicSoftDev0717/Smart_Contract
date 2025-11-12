// scripts/checkStats.js
const { ethers } = require("hardhat");
const { PRESALE_ADDR } = require("./constants");

const fmt = (n, d = 18) => ethers.formatUnits(n ?? 0n, d);
const nowTs = () => Math.floor(Date.now() / 1000);

function stageStatus(s) {
  const now = nowTs();
  const notStarted = s.startTime && Number(s.startTime) > now;
  const expired = s.endTime && Number(s.endTime) > 0 && Number(s.endTime) <= now;
  const soldOut = s.capTokens && s.soldTokens >= s.capTokens;
  const usdCapped = s.maxUsdRaise > 0n && s.usdRaised >= s.maxUsdRaise;
  const active = !s.paused && !notStarted && !expired && !soldOut && !usdCapped;
  return {
    active,
    notStarted,
    expired,
    soldOut,
    usdCapped,
    paused: s.paused
  };
}

async function main() {
  console.log("\n=== Presale Stats ===");

  if (!PRESALE_ADDR) {
    console.error("❌ PRESALE_ADDR not set in constants.js / .env");
    process.exit(1);
  }

  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR);

  try {
    // Header
    const [sold, usd, buyers] = await presale.getOverallStats();
    const count = Number(await presale.stagesCount());
    const current = Number(await presale.currentStage());
    const claimEnabled = await presale.claimEnabled();
    const globalPause = await presale.globalPause?.().catch(() => false);

    console.log(` Presale: ${PRESALE_ADDR}`);
    console.log(` Now:     ${nowTs()} (unix)`);
    console.log(` Stage:   ${current}/${Math.max(0, count - 1)}`);
    console.log(` Claim:   ${claimEnabled ? "ENABLED" : "DISABLED"}`);
    console.log(` Global pause: ${globalPause ? "ON" : "OFF"}`);

    console.log("\n== Overall ==");
    console.log(`Total tokens sold: ${fmt(sold)} `);
    console.log(`Total USD raised:  ${fmt(usd)} `);
    console.log(`Unique buyers:     ${buyers.toString()}`);

    // Per-stage
    console.log("\n== Per-stage ==");
    let aggTokens = 0n, aggUsd = 0n;

    for (let i = 0; i < count; i++) {
      const s = await presale.getStage(i);
      const stat = stageStatus(s);

      const priceUsd = fmt(s.usdPerToken); // USD×1e18 per token
      const soldT = fmt(s.soldTokens);
      const capT = fmt(s.capTokens);
      const usdRaised = fmt(s.usdRaised);
      const maxUsd = s.maxUsdRaise > 0n ? fmt(s.maxUsdRaise) : "∞";
      const start = Number(s.startTime) || 0;
      const end = Number(s.endTime) || 0;

      console.log(
        `#${i} ` +
        `[${stat.active ? "ACTIVE" :
           stat.paused ? "PAUSED" :
           stat.notStarted ? "NOT_STARTED" :
           stat.expired ? "EXPIRED" :
           stat.soldOut ? "SOLD_OUT" :
           stat.usdCapped ? "USD_CAPPED" : "UNKNOWN"}] ` +
        `price=$${priceUsd}/token, sold=${soldT}/${capT}, usd=${usdRaised}/${maxUsd}, ` +
        `time=[${start}→${end}]`
      );

      aggTokens += s.soldTokens;
      aggUsd += s.usdRaised;
    }

    // Assertions
    console.log("\n== Assertions ==");
    const sumsMatchTokens = aggTokens === sold;
    const sumsMatchUsd = aggUsd === usd;
    console.log(`Σ(stage.soldTokens) == totalTokenSold: ${sumsMatchTokens ? "✅" : "❌"}`);
    console.log(`Σ(stage.usdRaised)  == totalUsdRaised: ${sumsMatchUsd ? "✅" : "❌"}`);

    if (!sumsMatchTokens || !sumsMatchUsd) {
      console.warn(
        "⚠️ Totals mismatch. Re-check recent transactions or stage boundaries (time/cap/usdCap)."
      );
    }

  } catch (err) {
    console.error("\n❌ Failed to read presale stats.");
    if (err.shortMessage?.includes("execution reverted")) {
      console.error("   → Contract call reverted (wrong address or network).");
    } else if (err.code === "NETWORK_ERROR") {
      console.error("   → Network/RPC issue. Verify --network and RPC URL.");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
    process.exit(1);
  }
}

main().catch(console.error);
