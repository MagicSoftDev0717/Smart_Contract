// 

// scripts/pauseStage.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR } = require("./constants");

async function main() {
  const [stageIndexArg, actionArg] = process.argv.slice(2);

  console.log("\n=== Stage Pause/Unpause Script ===");

  if (stageIndexArg === undefined || !["pause", "unpause"].includes(actionArg || "")) {
    console.log("Usage: node scripts/pauseStage.js <stageIndex> <pause|unpause>");
    console.log("Example: node scripts/pauseStage.js 0 pause");
    process.exit(1);
  }

  const stageIndex = Number(stageIndexArg);
  const pauseVal = actionArg === "pause";

  if (!PRESALE_ADDR) {
    console.error("❌ PRESALE_ADDR not set in constants.js or .env.");
    process.exit(1);
  }

  const owner = await getWallet("owner");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, owner);

  console.log(`\n Owner: ${owner.address}`);
  console.log(` Presale: ${PRESALE_ADDR}`);
  console.log(` Target stage: ${stageIndex} → ${pauseVal ? "PAUSE" : "UNPAUSE"}`);

  // --- Pre-checks ---
  try {
    const onchainOwner = await presale.owner();
    if (onchainOwner.toLowerCase() !== owner.address.toLowerCase()) {
      console.error(`❌ Wallet mismatch: contract owner is ${onchainOwner}`);
      process.exit(1);
    }

    const totalStages = Number(await presale.stagesCount());
    if (stageIndex >= totalStages) {
      console.error(`❌ Invalid stage index. Contract only has ${totalStages} stages.`);
      process.exit(1);
    }

    const stage = await presale.getStage(stageIndex);
    console.log(
      `   Current stage status: paused=${stage.paused}, sold=${ethers.formatUnits(stage.soldTokens, 18)} tokens`
    );
  } catch (err) {
    console.error("❌ Failed to fetch presale state. Check contract address or network.");
    console.error("   →", err.shortMessage || err.message);
    process.exit(1);
  }

  // --- Execute pause/unpause ---
  try {
    console.log(`\n Sending transaction...`);
    const tx = await presale.pauseStage(stageIndex, pauseVal);
    console.log(`   Tx hash: ${tx.hash}`);
    await tx.wait();
    console.log(`✅ Stage ${stageIndex} successfully ${pauseVal ? "paused" : "unpaused"}.`);
  } catch (err) {
    console.error("\n❌ Transaction failed!");
    if (err.shortMessage?.includes("caller is not the owner")) {
      console.error("   → This wallet is not the contract owner.");
    } else if (err.shortMessage?.includes("range")) {
      console.error("   → Invalid stage index (out of range).");
    } else if (err.code === "INSUFFICIENT_FUNDS") {
      console.error("   → Not enough ETH to cover gas fees.");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
  }
}

main().catch(console.error);
