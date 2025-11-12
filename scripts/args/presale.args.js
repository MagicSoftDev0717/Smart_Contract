require("dotenv").config();
// Must match EXACTLY what you deployed with.
module.exports = [
  process.env.TOKEN_ADDR,           // from .env or scripts/constants.js
  process.env.USDT_ADDR,
  process.env.TREASURY,
  process.env.ORACLE_ETH_USD,
  require("../stages.deployed.json") // write this during deploy
];
