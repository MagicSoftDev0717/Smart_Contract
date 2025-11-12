// // scripts/deploy.js
// const hre = require("hardhat");

// async function main() {
//   const [owner] = await hre.ethers.getSigners();

//   console.log("Deploying with:", owner.address);

//   // 1️⃣ Deploy token
//   const Token = await hre.ethers.getContractFactory("ProjectToken");
//   const token = await Token.deploy("Project Token", "PTKN", owner.address);
// //   const token = await Token.deploy(owner.address);
//   await token.waitForDeployment();
//   console.log("Token deployed:", await token.getAddress());

//   // 2️⃣ Configure stages
//   const now = Math.floor(Date.now() / 1000);
//   const stages = [
//     { usdPerToken: hre.ethers.parseUnits("0.002", 18),
//       capTokens: hre.ethers.parseUnits("500000", 18),
//       soldTokens: 0,
//       usdRaised: 0,
//       maxUsdRaise: hre.ethers.parseUnits("1000", 18),
//       startTime: now,
//       endTime: now + 86400,
//       paused: false
//     },
//     { usdPerToken: hre.ethers.parseUnits("0.003", 18),
//       capTokens: hre.ethers.parseUnits("500000", 18),
//       soldTokens: 0,
//       usdRaised: 0,
//       maxUsdRaise: hre.ethers.parseUnits("1000", 18),
//       startTime: now + 86400,
//       endTime: now + 172800,
//       paused: false
//     }
//   ];

//   // 3️⃣ Deploy presale
//   const Presale = await hre.ethers.getContractFactory("ProjectPresale");
//   console.log({
//   token: await token.getAddress(),
//   usdt: process.env.USDT_SEPOLIA,
//   treasury: process.env.TREASURY,
//   oracle: process.env.ORACLE_ETH_USD,
//   stages
// });

//   const presale = await Presale.deploy(
//     await token.getAddress(),
//     process.env.USDT_SEPOLIA,
//     process.env.TREASURY,
//     process.env.ORACLE_ETH_USD,
//     stages
//   );
//   await presale.waitForDeployment();
//   console.log("Presale deployed:", await presale.getAddress());

//   // 4️⃣ Fund presale with tokens
//   const SALE_TOKENS = hre.ethers.parseUnits("1000000", 18);
//   const tx = await token.transfer(await presale.getAddress(), SALE_TOKENS);
//   await tx.wait();
//   console.log("Presale funded with", SALE_TOKENS.toString(), "tokens");

//   console.log("✅ Deployment complete!");
// }

// main().catch((e) => {
//   console.error(e);
//   process.exit(1);
// });


// scripts/deploy.js
require("dotenv").config();
const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log(`\nDeploying with: ${deployer.address}`);

    const {
        USDT_SEPOLIA,
        ORACLE_ETH_USD,
        TREASURY,
    } = process.env;


    // --- 1. Deploy ProjectToken ---------------------------------------------
    const Token = await hre.ethers.getContractFactory("ProjectToken");
    const token = await Token.deploy("Project Token", "PTKN", TREASURY);
    await token.waitForDeployment();

    const tokenAddr = await token.getAddress();
    console.log(`✅ Token deployed at: ${tokenAddr}`);

    // --- 2. Define presale stages ------------------------------------------
    // (price in USD×1e18, token cap, startTime, endTime)

    const now = Math.floor(Date.now() / 1000);
    const oneWeek = 7 * 24 * 60 * 60;

    const stages = [
        [
            hre.ethers.parseUnits("0.001", 18),
            hre.ethers.parseUnits("2000000000", 18),
            0,
            0,
            0,
            now,
            now + oneWeek,
            false,
        ],
        [
            hre.ethers.parseUnits("0.002", 18),
            hre.ethers.parseUnits("3000000000", 18),
            0,
            0,
            0,
            now + oneWeek,
            now + 2 * oneWeek,
            false,
        ],
        [
            hre.ethers.parseUnits("0.003", 18),
            hre.ethers.parseUnits("5000000000", 18),
            0,
            0,
            0,
            now + 2 * oneWeek,
            now + 3 * oneWeek,
            false,
        ],
    ];

    // console.log("Prepared stages:", stages);

    // Write stages used for verification (exact constructor arg)
    const fs = require("node:fs");
    // Replacer that turns all bigint values into strings
    const bigintReplacer = (_key, value) =>
        typeof value === "bigint" ? value.toString() : value;

    fs.mkdirSync("scripts", { recursive: true });
    fs.writeFileSync(
        "scripts/stages.deployed.json",
        JSON.stringify(stages, bigintReplacer, 2) // 👈 use replacer here
    );
    console.log("✅ Wrote scripts/stages.deployed.json for later verification.");



    const Presale = await hre.ethers.getContractFactory("ProjectPresale");
    const presale = await Presale.deploy(
        tokenAddr,
        USDT_SEPOLIA,
        TREASURY,
        ORACLE_ETH_USD,
        stages
    );
    await presale.waitForDeployment();


    const presaleAddr = await presale.getAddress();
    console.log(`✅ Presale deployed at: ${presaleAddr}`);

    // --- 3. Post-deployment setup ------------------------------------------
    // (Optional) Approve Presale to transfer tokens if claim distribution later
    // But since buyers claim directly from presale, you'll transfer tokens to it:
    const totalPresaleTokens = hre.ethers.parseUnits("3000000000", 18);
    console.log(`Transferring presale allocation to presale contract...`);
    const tokenTx = await token
        .connect(deployer)
        .transfer(presaleAddr, totalPresaleTokens);
    await tokenTx.wait();
    console.log("✅ Presale allocation transferred.");

    // --- 4. Verification (wait few blocks before verifying) ----------------
    console.log("\nWaiting 6 blocks before verifying...");
    await presale.deploymentTransaction().wait(5);
    await hre.run("verify:verify", {
        address: tokenAddr,
        constructorArguments: ["Project Token", "PTKN", TREASURY],
    });

    await hre.run("verify:verify", {
        address: presaleAddr,
        constructorArguments: [
            tokenAddr,
            USDT_SEPOLIA,
            TREASURY,
            ORACLE_ETH_USD,
            stages,
        ],
    });

    console.log("\n🎉 Deployment & verification complete!");
    console.log(`Token:   ${tokenAddr}`);
    console.log(`Presale: ${presaleAddr}`);
    console.log(`Treasury: ${TREASURY}`);
}

main().catch((err) => {
    console.error(err);
    process.exitCode = 1;
});
