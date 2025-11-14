// scripts/rescueUnsold.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR, TOKEN_ADDR } = require("./constants");

async function main() {
  const [amountStr] = process.argv.slice(2);
  if (!amountStr) {
    console.log("Usage: node scripts/rescueUnsold.js <amountTokens>");
    process.exit(1);
  }
  const amount = ethers.parseUnits(amountStr, 18);
  const owner = await getWallet("owner");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, owner);
  const token = await ethers.getContractAt("ProjectToken", TOKEN_ADDR, owner);
  const bal = await token.balanceOf(PRESALE_ADDR);
  console.log("Presale token balance:", ethers.formatUnits(bal, 18));
  if (bal < amount) {
    console.log("⚠️ Requested amount exceeds presale balance; exiting.");
    process.exit(1);
  }
  const tx = await presale.rescueUnsoldToTreasury(amount); // or rescueERC20(TOKEN_ADDR, amount)
  console.log("rescueUnsold tx:", tx.hash);
  await tx.wait();
  console.log("✅ Unsold tokens rescued to treasury.");
}
main().catch(console.error);
