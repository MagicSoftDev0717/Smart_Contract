// const { ethers } = require("hardhat");
// const { getWallet } = require("./wallet");

// async function main() {
//   const buyer = await getWallet("buyer");
//   const presale = await ethers.getContractAt("ProjectPresale", "0xPresaleAddress", buyer);
//   const token = await ethers.getContractAt("ProjectToken", "0xTokenAddress", buyer);

//   const before = await token.balanceOf(buyer.address);
//   const tx = await presale.claim(false);
//   await tx.wait();
//   const after = await token.balanceOf(buyer.address);

//   console.log("Claimed tokens:", after - before);
// }
// main();

// scripts/claim.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR, TOKEN_ADDR } = require("./constants");

const STAKE = (process.env.STAKE || "false").toLowerCase() === "true";

async function main() {
  console.log("\n=== Claim Tokens Script ===");

  if (!PRESALE_ADDR || !TOKEN_ADDR) {
    console.error("❌ PRESALE_ADDR or TOKEN_ADDR not set in constants.js / .env");
    process.exit(1);
  }

  const buyer = await getWallet("buyer");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, buyer);
  const token = await ethers.getContractAt("ProjectToken", TOKEN_ADDR, buyer);

  console.log(` Buyer: ${buyer.address}`);
  console.log(` Presale: ${PRESALE_ADDR}`);
  console.log(` Token:   ${TOKEN_ADDR}`);
  console.log(` Claim with stake=${STAKE}`);

  try {
    // --- Step 1: Pre-check ---
    const claimEnabled = await presale.claimEnabled();
    const purchased = await presale.purchased(buyer.address);
    const tokenBalBefore = await token.balanceOf(buyer.address);

    console.log(`\n Claim Enabled: ${claimEnabled}`);
    console.log(` Purchased (unclaimed): ${ethers.formatUnits(purchased, 18)} tokens`);
    console.log(` Current token balance: ${ethers.formatUnits(tokenBalBefore, 18)} tokens`);

    if (!claimEnabled) {
      console.error("❌ Claim is not enabled yet. The owner must call toggleClaim(true).");
      process.exit(1);
    }
    if (purchased == 0n) {
      console.error("❌ No tokens to claim. Either you didn’t buy, or already claimed.");
      process.exit(1);
    }

    // --- Step 2: Claim transaction ---
    console.log("\n Sending claim transaction...");
    const tx = await presale.claim(STAKE);
    console.log(`   Tx hash: ${tx.hash}`);
    await tx.wait();

    // --- Step 3: Post-check ---
    const tokenBalAfter = await token.balanceOf(buyer.address);
    const claimed = tokenBalAfter - tokenBalBefore;

    console.log(`\n✅ Claim successful!`);
    console.log(` Claimed tokens: ${ethers.formatUnits(claimed, 18)} (${claimed} wei units)`);
    console.log(` New balance: ${ethers.formatUnits(tokenBalAfter, 18)} tokens`);
  } catch (err) {
    console.error("\n❌ Claim failed!");
    if (err.shortMessage?.includes("claim off")) {
      console.error("   → Claiming is disabled. Owner must toggleClaim(true).");
    } else if (err.shortMessage?.includes("none")) {
      console.error("   → You have no unclaimed tokens or already claimed.");
    } else if (err.shortMessage?.includes("no stake mgr")) {
      console.error("   → Staking manager not set, but claim(true) was used.");
    } else if (err.shortMessage?.includes("ERC20")) {
      console.error("   → Token transfer failed — presale contract may lack enough tokens.");
    } else if (err.code === "INSUFFICIENT_FUNDS") {
      console.error("   → Not enough ETH in wallet to cover gas fees.");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
  }
}

main().catch(console.error);
