// const { ethers } = require("hardhat");
// const { getWallet } = require("./wallet");
// const { PRESALE_ADDR } = require("./constants");
// async function main() {
//   const w = await getWallet("owner");
//   const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, w);
//   const tx = await presale.manualAdvance(1); // Move to stage 1
//   console.log("Manual advance tx:", tx.hash);
//   await tx.wait();
// }
// main();


// scripts/manualAdvance.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR } = require("./constants");

async function main() {
  const [targetArg] = process.argv.slice(2);
  console.log("\n=== Manual Stage Advance Script ===");

  if (targetArg === undefined) {
    console.log("Usage: node scripts/manualAdvance.js <stageIndex>");
    console.log("Example: node scripts/manualAdvance.js 1");
    process.exit(1);
  }

  const newStage = Number(targetArg);
  const owner = await getWallet("owner");

  if (!PRESALE_ADDR) {
    console.error("❌ PRESALE_ADDR not set in constants.js or .env");
    process.exit(1);
  }

  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, owner);

  console.log(`🧾 Owner: ${owner.address}`);
  console.log(`🔗 Presale: ${PRESALE_ADDR}`);
  console.log(`🎯 Target stage: ${newStage}`);

  try {
    const onchainOwner = await presale.owner();
    if (onchainOwner.toLowerCase() !== owner.address.toLowerCase()) {
      console.error(`❌ Wallet mismatch: contract owner is ${onchainOwner}`);
      process.exit(1);
    }

    const totalStages = Number(await presale.stagesCount());
    const currentStage = Number(await presale.currentStage());
    console.log(`📊 Current stage: ${currentStage}/${totalStages - 1}`);

    if (newStage >= totalStages) {
      console.error(`❌ Invalid stage index. Contract has only ${totalStages} stages.`);
      process.exit(1);
    }
    if (newStage === currentStage) {
      console.error(`⚠️ Already at stage ${currentStage}. Nothing to advance.`);
      process.exit(1);
    }

    const stage = await presale.getStage(currentStage);
    const now = Math.floor(Date.now() / 1000);
    const timeActive =
      stage.endTime === 0
        ? false
        : now < Number(stage.endTime) && now >= Number(stage.startTime);
    const soldOut = Number(stage.soldTokens) >= Number(stage.capTokens);
    const expired = stage.endTime > 0 && now >= Number(stage.endTime);

    console.log(
      `   Stage ${currentStage} status: paused=${stage.paused}, sold=${ethers.formatUnits(
        stage.soldTokens,
        18
      )}, cap=${ethers.formatUnits(stage.capTokens, 18)}, timeActive=${timeActive}`
    );

    if (!soldOut && !expired) {
      console.log("⚠️ Current stage may still be active. The contract might revert with 'current active'.");
    }

    console.log("\n🚀 Sending manualAdvance transaction...");
    const tx = await presale.manualAdvance(newStage);
    console.log(`   Tx hash: ${tx.hash}`);
    await tx.wait();
    console.log(`✅ Stage successfully advanced from ${currentStage} → ${newStage}`);
  } catch (err) {
    console.error("\n❌ Transaction failed!");
    if (err.shortMessage?.includes("caller is not the owner")) {
      console.error("   → This wallet is not the contract owner.");
    } else if (err.shortMessage?.includes("range")) {
      console.error("   → Invalid stage index (out of range).");
    } else if (err.shortMessage?.includes("same")) {
      console.error("   → Tried to advance to the same stage.");
    } else if (err.shortMessage?.includes("current active")) {
      console.error("   → The current stage has not yet ended (time, cap, or USD limit not met).");
    } else if (err.code === "INSUFFICIENT_FUNDS") {
      console.error("   → Not enough ETH to cover gas fees.");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
  }
}

main().catch(console.error);
