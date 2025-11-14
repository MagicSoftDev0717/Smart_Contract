// scripts/addStageSimple.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR } = require("./constants");

async function main() {
  const [price, cap, maxUsd, pausedArg] = process.argv.slice(2);
  if (!price || !cap) {
    console.log("Usage: node scripts/addStageSimple.js <usdPerToken> <capTokens> [maxUsdRaise=0] [paused=false]");
    process.exit(1);
  }
  const owner = await getWallet("owner");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, owner);
  const usdPerToken = ethers.parseUnits(price, 18);
  const capTokens = ethers.parseUnits(cap, 18);
  const maxUsdRaise = maxUsd ? ethers.parseUnits(maxUsd, 18) : 0n;
  const paused = (pausedArg || "false").toLowerCase() === "true";
  const tx = await presale.addStageSimple(usdPerToken, capTokens, maxUsdRaise, paused);
  console.log("addStageSimple tx:", tx.hash);
  await tx.wait();
  console.log("✅ Stage added.");
}
main().catch(console.error);
