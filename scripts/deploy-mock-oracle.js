
const hre = require("hardhat");
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying MockOracle with:", deployer.address);
  const MockOracle = await hre.ethers.getContractFactory("MockOracle");
  const oracle = await MockOracle.deploy();
  await oracle.waitForDeployment();
  console.log("✅ MockOracle deployed at:", await oracle.getAddress());
}
main().catch(console.error);
