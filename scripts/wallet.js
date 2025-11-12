require("dotenv").config();
const { ethers } = require("hardhat");

async function getWallet(kind = "owner") {
  const pk = kind === "buyer" ? process.env.PRIVATE_KEY_BUYER : process.env.PRIVATE_KEY_OWNER;
  if (!pk) throw new Error(`Missing private key for ${kind}`);
  const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
  return new ethers.Wallet(pk, provider);
}

module.exports = { getWallet };
