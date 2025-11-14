// scripts/claimStake.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR, TOKEN_ADDR } = require("./constants");

async function main() {
  const buyer = await getWallet("buyer");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, buyer);
  const token = await ethers.getContractAt("ProjectToken", TOKEN_ADDR, buyer);

  const before = await token.balanceOf(buyer.address);
  console.log("\n== claim(stake=true) ==");
  console.log("Token balance before:", ethers.formatUnits(before, 18));

  let tx;
  try {
    tx = await presale.claim(true);
    console.log("tx:", tx.hash);
  } catch (err) {
    console.error("❌ claim(true) reverted.");
    if (err.shortMessage?.includes("claim off")) console.error(" → Enable claim first: enableClaim.js on");
    else if (err.shortMessage?.includes("no stake mgr")) console.error(" → Set staking manager before claiming with stake.");
    else if (err.shortMessage?.includes("none")) console.error(" → Nothing to claim (no purchased balance).");
    else console.error(" →", err.shortMessage || err.message);
    process.exit(1);
  }
  await tx.wait();

  const after = await token.balanceOf(buyer.address);
  console.log("Token balance after:", ethers.formatUnits(after, 18));
  console.log("Note: With stake=true, tokens should NOT appear in wallet; they were deposited to staking manager.");
  console.log("✅ Done.");
}

main().catch(console.error);
