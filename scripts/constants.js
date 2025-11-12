// scripts/constants.js
require("dotenv").config();

module.exports = {
  TOKEN_ADDR: process.env.TOKEN_ADDR || "0x09A49A33CF6Ca6a9309378141C5D0559209064b5",
  PRESALE_ADDR: process.env.PRESALE_ADDR || "0xd431Ac45C403Fae89D27eA91655C04FEe8cFab81",
  USDT_ADDR: process.env.USDT_ADDR || "0x2aB6245Abd22f1c57748C88899e82a1b070Accb3",
};
