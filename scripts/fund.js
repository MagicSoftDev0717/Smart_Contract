// scripts/fund.js
const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { TOKEN_ADDR, PRESALE_ADDR } = require("./constants");

async function main() {
//   const [amountStr] = process.argv.slice(2);
    const amountStr = process.env.AMOUNT;
  if (!amountStr) {
    console.log("Usage: node scripts/fund.js <amountTokens>");
    process.exit(1);
  }
  const amount = ethers.parseUnits(amountStr, 18);

  const owner = await getWallet("owner"); // must hold the sale allocation
  const token = await ethers.getContractAt("ProjectToken", TOKEN_ADDR, owner);

  const tx = await token.transfer(PRESALE_ADDR, amount);
  console.log(`Funding presale with ${amountStr} tokens. tx:`, tx.hash);
  await tx.wait();
  console.log("Funded.");
}

main().catch(console.error);
