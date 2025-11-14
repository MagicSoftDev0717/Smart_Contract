// scripts/earlyEndAndRollover.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR } = require("./constants");

const fmt = (n, d = 18) => {
  try { return ethers.formatUnits(n ?? 0n, d); } catch { return (n ?? 0n).toString(); }
};

async function main() {
  console.log("\n=== earlyEndAndRollover ===");

  if (!PRESALE_ADDR) {
    console.error("❌ PRESALE_ADDR not set in scripts/constants.js / .env");
    process.exit(1);
  }

  const owner = await getWallet("owner");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, owner);

  try {
    const onchainOwner = await presale.owner();
    if (onchainOwner.toLowerCase() !== owner.address.toLowerCase()) {
      console.error(`❌ Wallet mismatch: contract owner is ${onchainOwner}, you are ${owner.address}`);
      process.exit(1);
    }

    const cur = Number(await presale.currentStage());
    const count = Number(await presale.stagesCount());
    if (cur >= count) {
      console.error(`❌ No active stage. currentStage=${cur}, stagesCount=${count}`);
      process.exit(1);
    }

    const sBefore = await presale.getStage(cur);
    console.log(`📍 Current stage: #${cur}/${count - 1}`);
    console.log(`   soldTokens=${fmt(sBefore.soldTokens)} capTokens=${fmt(sBefore.capTokens)} paused=${sBefore.paused}`);

    if (sBefore.paused) {
      console.error("❌ Current stage is paused. Unpause or use cancel function.");
      process.exit(1);
    }
    if (sBefore.soldTokens >= sBefore.capTokens) {
      console.error("❌ Nothing to end: stage is already fully sold.");
      process.exit(1);
    }

    console.log("\n Sending tx: earlyEndAndRollover()");
    const tx = await presale.earlyEndAndRollover();
    console.log("   tx hash:", tx.hash);
    await tx.wait();

    const curAfter = Number(await presale.currentStage());
    console.log(`\n✅ Done. currentStage advanced to: #${curAfter}`);

    // Show quick snapshot of affected stages
    const sCurAfter = await presale.getStage(cur);
    console.log(`\n#${cur} (sealed): soldTokens=${fmt(sCurAfter.soldTokens)} capTokens=${fmt(sCurAfter.capTokens)} paused=${sCurAfter.paused}`);

    if (cur + 1 < count) {
      const sNext = await presale.getStage(cur + 1);
      console.log(`#${cur + 1} (next): capTokens=${fmt(sNext.capTokens)} soldTokens=${fmt(sNext.soldTokens)} paused=${sNext.paused}`);
    } else {
      console.log("ℹ️ There was no next stage to receive rollover (last stage).");
    }
  } catch (err) {
    console.error("\n❌ earlyEndAndRollover failed.");
    if (err.shortMessage?.includes("no stage")) {
      console.error("   → No active stage available.");
    } else if (err.shortMessage?.includes("paused")) {
      console.error("   → Current stage is paused; unpause or use cancel function.");
    } else if (err.shortMessage?.includes("nothing to end")) {
      console.error("   → Stage already fully sold (no remaining capacity).");
    } else if (err.code === "INSUFFICIENT_FUNDS") {
      console.error("   → Not enough ETH for gas in owner wallet.");
    } else {
      console.error("   →", err.shortMessage || err.message);
    }
    process.exit(1);
  }
}

main().catch(console.error);
