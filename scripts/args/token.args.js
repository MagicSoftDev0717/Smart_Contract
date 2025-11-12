require("dotenv").config();
module.exports = [
  process.env.TOKEN_NAME   || "Project Token",
  process.env.TOKEN_SYMBOL || "PTKN",
  process.env.TREASURY
];
