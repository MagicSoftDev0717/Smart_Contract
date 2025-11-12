// // scripts/enableClaim.js
// const { ethers } = require("hardhat");
// const { getWallet } = require("./wallet");
// const { PRESALE_ADDR } = require("./constants");

// async function main() {
//   const [onOff] = process.argv.slice(2);
//   if (!["on", "off"].includes(onOff || "")) {
//     console.log("Usage: node scripts/enableClaim.js <on|off>");
//     process.exit(1);
//   }
//   const v = onOff === "on";

//   const owner = await getWallet("owner");
//   const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, owner);

//   const tx = await presale.toggleClaim(v);
//   console.log(`toggleClaim(${v}) tx:`, tx.hash);
//   await tx.wait();
//   console.log("Done.");
// }

// main().catch(console.error);

// scripts/enableClaim.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR } = require("./constants");

async function main() {
  console.log("\n=== Toggle Claim Script ===");

  const [onOff] = process.argv.slice(2);
  if (!["on", "off"].includes(onOff || "")) {
    console.log("Usage: node scripts/enableClaim.js <on|off>");
    console.log("Example: node scripts/enableClaim.js on");
    process.exit(1);
  }

  const enable = onOff === "on";

  if (!PRESALE_ADDR) {
    console.error("❌ PRESALE_ADDR not set in constants.js / .env");
    process.exit(1);
  }

  const owner = await getWallet("owner");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, owner);

  console.log(` Owner: ${owner.address}`);
  console.log(` Presale: ${PRESALE_ADDR}`);
  console.log(` Action: toggleClaim(${enable})`);

  try {
    // --- Step 1: Verify owner & current status ---
    const onchainOwner = await presale.owner();
    if (onchainOwner.toLowerCase() !== owner.address.toLowerCase()) {
      console.error(`❌ Wallet mismatch: contract owner is ${onchainOwner}`);
      process.exit(1);
    }

    const currentStatus = await presale.claimEnabled();
    console.log(` Current claimEnabled: ${currentStatus}`);

    if (currentStatus === enable) {
      console.log(`⚠️  Claim is already ${enable ? "enabled" : "disabled"}.`);
      process.exit(0);
    }

    // --- Step 2: Send transaction ---
    console.log("\n Sending toggleClaim transaction...");
    const tx = await presale.toggleClaim(enable);
    console.log(`   Tx hash: ${tx.hash}`);
    await tx.wait();

    // --- Step 3: Confirm change ---
    const newStatus = await presale.claimEnabled();
    console.log(`✅ Claim status updated successfully → claimEnabled=${newStatus}`);
  } catch (err) {
    console.error("\n❌ Transaction failed!");
    if (err.shortMessage?.includes("caller is not the owner")) {
      console.error("   → This wallet is not the contract owner.");
    } else if (err.code === "INSUFFICIENT_FUNDS") {
      console.error("   → Not enough ETH to pay gas fees.");
    } else if (err.shortMessage?.includes("execution reverted")) {
      console.error("   → Contract call reverted (check address or network).");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
  }
}

main().catch(console.error);
