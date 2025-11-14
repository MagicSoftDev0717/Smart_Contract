const { ethers } = require("hardhat");
const { getWallet } = require("./wallet");
const { PRESALE_ADDR } = require("./constants");

const PRESALE = PRESALE_ADDR;
const ETH_AMOUNT = process.env.ETH_AMOUNT || "0.02"; // in ETH
const STAKE = (process.env.STAKE || "false").toLowerCase() === "true";

async function main() {
  if (!PRESALE) throw new Error("Set PRESALE_ADDR in constants.js");

  const buyer = await getWallet("buyer");
  const presale = await ethers.getContractAt("ProjectPresale", PRESALE, buyer);

  const valueWei = ethers.parseEther(ETH_AMOUNT);
  const balanceWei = await ethers.provider.getBalance(buyer.address);
  const balanceEth = Number(ethers.formatEther(balanceWei));

  console.log(`\n Buyer: ${buyer.address}`);
  console.log(`   Balance: ${balanceEth.toFixed(6)} ETH`);
  console.log(`   Attempting to send: ${ETH_AMOUNT} ETH (stake=${STAKE})`);

  if (balanceWei < valueWei) {
    console.error(
      `❌ Insufficient funds. You have ${balanceEth} ETH but need at least ${ETH_AMOUNT} ETH + gas (~0.0003 ETH).`
    );
    return;
  }

  try {
    const gasEstimate = await presale.buyWithEth.estimateGas(STAKE, { value: valueWei });
    console.log(`   Estimated gas: ${gasEstimate.toString()}`);

    const tx = await presale.buyWithEth(STAKE, { value: valueWei });
    console.log(` Tx sent: ${tx.hash}`);
    await tx.wait();
    ////Add new for M2--////////
    const receipt = await tx.wait();
    const presaleFactory = await ethers.getContractFactory("ProjectPresale");
    const iface = presaleFactory.interface;

    for (const log of receipt.logs) {
      try {
        const parsed = iface.parseLog(log);
        if (parsed?.name === "TokensBoughtSplit" || parsed?.name === "TokensBoughtAndStakedSplit") {
          const { stageIndexes, stageUsd, stageTokens } = parsed.args;
          console.log("Stage indexes:", stageIndexes.map(n => Number(n)));
          console.log("USD parts:", stageUsd.map(u => ethers.formatUnits(u, 18)));
          console.log("Token parts:", stageTokens.map(t => ethers.formatUnits(t, 18)));
        }
      } catch (_) { }
    }

    console.log("✅ Buy transaction confirmed.");
  } catch (err) {
    console.error("\n❌ Transaction failed.");
    if (err.code === "INSUFFICIENT_FUNDS") {
      console.error(
        "   → Not enough ETH for both the 0.02 ETH payment and gas fees.\n" +
        "     Please top up your Sepolia wallet slightly (e.g. to 0.03 ETH)."
      );
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
  }
}
main().catch(console.error);



