const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying MockUSDT with:", deployer.address);

  const MockUSDT = await hre.ethers.getContractFactory("MockUSDT");
  const usdt = await MockUSDT.deploy();
  await usdt.waitForDeployment();

  console.log("✅ Mock USDT deployed at:", await usdt.getAddress());
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
