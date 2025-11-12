// scripts/checkBalance.js
const { ethers } = require("hardhat");
const { TOKEN_ADDR, PRESALE_ADDR } = require("./constants");

async function main() {
  console.log("\n=== Presale Balance Check ===");

  if (!PRESALE_ADDR || !TOKEN_ADDR) {
    console.error("❌ Missing PRESALE_ADDR or TOKEN_ADDR in constants.js / .env");
    process.exit(1);
  }

  const provider = ethers.provider;

  try {
    // --- Check ETH balance ---
    console.log(` Presale address: ${PRESALE_ADDR}`);
    const ethBal = await provider.getBalance(PRESALE_ADDR);
    const ethBalReadable = ethers.formatEther(ethBal);
    console.log(` ETH Balance: ${ethBalReadable} ETH (${ethBal} wei)`);

    // --- Check token balance ---
    console.log(`\n Token address:   ${TOKEN_ADDR}`);
    const token = await ethers.getContractAt("ProjectToken", TOKEN_ADDR);
    const presaleTokenBal = await token.balanceOf(PRESALE_ADDR);

    const decimals = await token.decimals();
    const tokenBalReadable = ethers.formatUnits(presaleTokenBal, decimals);
    console.log(` Token Balance: ${tokenBalReadable} tokens (decimals=${decimals})`);

    // --- Sanity checks ---
    if (ethBal > 0n) {
      console.warn("⚠️ Warning: Presale contract holds ETH. It should normally forward funds to the treasury.");
    } else {
      console.log("✅ ETH balance check passed (no trapped funds).");
    }

    if (presaleTokenBal === 0n) {
      console.warn("⚠️ Warning: Presale contract holds 0 tokens. Make sure tokens were transferred for claims.");
    } else {
      console.log("✅ Token balance check passed.");
    }
  } catch (err) {
    console.error("\n❌ Failed to fetch balances!");
    if (err.shortMessage?.includes("execution reverted")) {
      console.error("   → Contract address might be invalid or not verified on this network.");
    } else if (err.code === "NETWORK_ERROR") {
      console.error("   → Network issue: check your RPC connection or Hardhat network setting.");
    } else {
      console.error("   → Error details:", err.shortMessage || err.message);
    }
  }
}

main().catch(console.error);

