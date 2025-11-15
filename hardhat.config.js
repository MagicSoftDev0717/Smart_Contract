require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY } = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
    },
  },
  networks: {
    sepolia: {
      url: SEPOLIA_RPC_URL || "",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY || "",
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    coinmarketcap: process.env.CMC_API_KEY || undefined,
  },
};