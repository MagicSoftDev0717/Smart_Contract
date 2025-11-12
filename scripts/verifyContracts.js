// scripts/verifyContracts.js
/**
 * One-button Etherscan verification for Token + Presale.
 * - Addresses are sourced from scripts/constants.js (with .env fallbacks).
 * - Constructor args (names, treasury, oracle, etc.) from .env.
 * - For the presale's Stage[] constructor arg, use a JS args file (recommended).
 *
 * Usage:
 *   node scripts/verifyContracts.js               # uses NETWORK=sepolia by default
 *   NETWORK=sepolia node scripts/verifyContracts.js
 *
 * If you created args files:
 *   npx hardhat verify --network $NETWORK --constructor-args scripts/args/token.args.js   $TOKEN_ADDR
 *   npx hardhat verify --network $NETWORK --constructor-args scripts/args/presale.args.js $PRESALE_ADDR
 */

const { execSync } = require("node:child_process");
const path = require("node:path");
require("dotenv").config();

const { TOKEN_ADDR, PRESALE_ADDR, USDT_ADDR } = require("./constants");

// ---- .env-configurable values ----
const NETWORK        = process.env.NETWORK || "sepolia";
const ETHERSCAN_KEY  = process.env.ETHERSCAN_API_KEY || "";
const TREASURY       = process.env.TREASURY || "";
const ORACLE_ETH_USD = process.env.ORACLE_ETH_USD || process.env.ORACLE || "";

const TOKEN_NAME     = process.env.TOKEN_NAME  || "Project Token";
const TOKEN_SYMBOL   = process.env.TOKEN_SYMBOL || "PTKN";

// Optional convenience: where your deploy script can dump the exact Stage[] JSON
const STAGES_JSON_PATH = process.env.PRESALE_STAGES_JSON
  || path.join(__dirname, "stages.deployed.json");

// Optional args files (recommended)
const TOKEN_ARGS_JS   = process.env.TOKEN_ARGS_JS   || path.join(__dirname, "args", "token.args.js");
const PRESALE_ARGS_JS = process.env.PRESALE_ARGS_JS || path.join(__dirname, "args", "presale.args.js");

function logHdr(title) {
  console.log("\n" + "=".repeat(10) + " " + title + " " + "=".repeat(10));
}

function ok(msg)     { console.log("✅ " + msg); }
function warn(msg)   { console.warn("⚠️  " + msg); }
function fail(msg)   { console.error("❌ " + msg); process.exit(1); }

function sh(cmd) {
  console.log("> " + cmd);
  try {
    execSync(cmd, { stdio: "inherit" });
    return true;
  } catch (e) {
    return false;
  }
}

async function main() {
  logHdr("Etherscan Verification");

  // --- sanity checks ---
  console.log(" Network:        ", NETWORK);
  console.log(" ETHERSCAN key:  ", ETHERSCAN_KEY ? "(set)" : "(missing)");
  console.log(" TOKEN_ADDR:     ", TOKEN_ADDR || "(missing)");
  console.log(" PRESALE_ADDR:   ", PRESALE_ADDR || "(missing)");
  console.log(" USDT_ADDR:      ", USDT_ADDR || "(missing)");
  console.log(" TREASURY:       ", TREASURY || "(missing)");
  console.log(" ORACLE_ETH_USD: ", ORACLE_ETH_USD || "(missing)");

  if (!ETHERSCAN_KEY) warn("ETHERSCAN_API_KEY is not set — verification will fail.");
  if (!TOKEN_ADDR)    fail("TOKEN_ADDR is not set (check scripts/constants.js or .env).");
  if (!PRESALE_ADDR)  fail("PRESALE_ADDR is not set (check scripts/constants.js or .env).");

  // =========================================================
  // 1) Verify ProjectToken with correct constructor args
  //    constructor(string name_, string symbol_, address initialRecipient)
  // =========================================================
  logHdr("ProjectToken");
  console.log(`Constructor args: ["${TOKEN_NAME}", "${TOKEN_SYMBOL}", ${TREASURY}]`);

  if (!TREASURY) warn("TREASURY is empty; token verification will likely fail.");

  // Prefer args file if present; otherwise inline args.
  let tokenVerified = false;
  const tokenArgsFileExists = (() => {
    try { require.resolve(TOKEN_ARGS_JS); return true; } catch { return false; }
  })();

  if (tokenArgsFileExists) {
    tokenVerified = sh(
      `npx hardhat verify --network ${NETWORK} --constructor-args "${TOKEN_ARGS_JS}" ${TOKEN_ADDR}`
    );
  } else {
    tokenVerified = sh(
      [
        "npx hardhat verify",
        `--network ${NETWORK}`,
        TOKEN_ADDR,
        `"${TOKEN_NAME}"`,
        `"${TOKEN_SYMBOL}"`,
        TREASURY
      ].join(" ")
    );
  }

  if (tokenVerified) {
    ok("Token verified (or already verified).");
  } else {
    warn(
      [
        "Token verification failed. Common causes:",
        "- Constructor args mismatch (name/symbol/recipient differ from deploy).",
        "- Wrong network or ETHERSCAN_API_KEY missing.",
        "- Recompiled bytecode differs from deployed bytecode."
      ].join("\n   ")
    );
  }

  // =========================================================
  // 2) Verify ProjectPresale
  //    constructor(address token, address usdt, address treasury, address oracle, Stage[] memory stages)
  //    For Stage[] you MUST pass the exact array used at deploy time.
  //    Strongly recommend using a JS args file that imports stages.deployed.json.
  // =========================================================
  logHdr("ProjectPresale");

  // Check if args file for the presale exists
  const presaleArgsFileExists = (() => {
    try { require.resolve(PRESALE_ARGS_JS); return true; } catch { return false; }
  })();

  if (!USDT_ADDR || !TREASURY || !ORACLE_ETH_USD) {
    warn("Missing one or more presale constructor addresses (USDT_ADDR / TREASURY / ORACLE_ETH_USD).");
  }

  // Try to help if stages JSON exists
  let stagesLoaded = false;
  try {
    const stages = require(STAGES_JSON_PATH);
    if (Array.isArray(stages) && stages.length > 0) {
      stagesLoaded = true;
      console.log(`Found stages JSON at: ${STAGES_JSON_PATH} (entries: ${stages.length})`);
    }
  } catch {
    warn(`No stages JSON found at ${STAGES_JSON_PATH}.`);
  }

  if (!presaleArgsFileExists) {
    warn(
      [
        "No presale args file found. Create one to include the Stage[] exactly as deployed.",
        "",
        "Example: scripts/args/presale.args.js",
        "-----------------------------------",
        "require('dotenv').config();",
        "module.exports = [",
        "  process.env.TOKEN_ADDR,",
        "  process.env.USDT_ADDR,",
        "  process.env.TREASURY,",
        "  process.env.ORACLE_ETH_USD,",
        "  require('../stages.deployed.json')",
        "];",
        ""
      ].join("\n")
    );
  }

  let presaleVerified = false;
  if (presaleArgsFileExists) {
    presaleVerified = sh(
      `npx hardhat verify --network ${NETWORK} --constructor-args "${PRESALE_ARGS_JS}" ${PRESALE_ADDR}`
    );
  } else {
    // We purposely do not attempt an inline verify because passing Stage[] on the CLI is error-prone.
    warn("Skipping presale verification because a constructor-args file was not found.");
  }

  if (presaleVerified) {
    ok("Presale verified (or already verified).");
  } else {
    warn(
      [
        "Presale not verified. To verify:",
        `  1) Ensure ${STAGES_JSON_PATH} contains the EXACT Stage[] used at deployment.`,
        `  2) Create ${PRESALE_ARGS_JS} exporting [token, usdt, treasury, oracle, stages].`,
        `  3) Run: npx hardhat verify --network ${NETWORK} --constructor-args ${PRESALE_ARGS_JS} ${PRESALE_ADDR}`
      ].join("\n   ")
    );
  }

  console.log("\nDone.");
}

main().catch((e) => {
  fail(e?.message || e);
});
