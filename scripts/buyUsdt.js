const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR, USDT_ADDR } = require("./constants");

const USDT_DECIMALS = 6;
const AMOUNT_USDT = process.env.USDT_AMOUNT || "100"; // 100 by default
const STAKE = (process.env.STAKE || "false").toLowerCase() === "true";

async function main() {
  const buyer = await getWallet("buyer");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE_ADDR, buyer);
  const usdt = await ethers.getContractAt("IERC20", USDT_ADDR, buyer);

  const amount = ethers.parseUnits(AMOUNT_USDT, USDT_DECIMALS);

  console.log(`\n🧾 Buyer: ${buyer.address}`);
  console.log(`   Attempting to buy ${AMOUNT_USDT} USDT worth of tokens (stake=${STAKE})`);

  // --- Step 1: Check balance ---
  const balance = await usdt.balanceOf(buyer.address);
  const formattedBal = Number(ethers.formatUnits(balance, USDT_DECIMALS));
  console.log(`   USDT Balance: ${formattedBal} USDT`);

  if (balance < amount) {
    console.error(`❌ Insufficient USDT balance. Need ${AMOUNT_USDT}, have only ${formattedBal}.`);
    return;
  }

  // --- Step 2: Check allowance ---
  const allowance = await usdt.allowance(buyer.address, PRESALE_ADDR);
  const formattedAllowance = Number(ethers.formatUnits(allowance, USDT_DECIMALS));

  if (allowance < amount) {
    console.log(`   Current allowance: ${formattedAllowance} USDT → approving now...`);
    const approveTx = await usdt.approve(PRESALE_ADDR, amount); //Grants the presale contract permission to pull amount(ex: 100) USDT from the buyer’s wallet.
    console.log(`   🧩 Approval Tx: ${approveTx.hash}`);
    await approveTx.wait();
    console.log("   ✅ Approval confirmed.");
  } else {
    console.log(`   ✅ Sufficient allowance: ${formattedAllowance} USDT`);
  }

  // --- Step 3: Attempt the purchase ---
  try {
    console.log(`\n🚀 Sending buyWithUsdt(${AMOUNT_USDT}, stake=${STAKE})...`);
    const tx = await presale.buyWithUsdt(amount, STAKE);
    console.log(`   Tx hash: ${tx.hash}`);
    await tx.wait();
    console.log("✅ Purchase confirmed successfully!");
  } catch (err) {
    console.error("\n❌ Purchase failed!");
    if (err.shortMessage?.includes("below min")) {
      console.error("   → The purchase amount is below the minimum allowed (50 USD).");
    } else if (err.shortMessage?.includes("paused")) {
      console.error("   → The presale or current stage is paused.");
    } else if (err.shortMessage?.includes("sold out")) {
      console.error("   → All tokens for the current stage are sold out.");
    } else if (err.shortMessage?.includes("no stake mgr")) {
      console.error("   → Staking manager not set, but stake=true was used.");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
  }
}

main().catch(console.error);
