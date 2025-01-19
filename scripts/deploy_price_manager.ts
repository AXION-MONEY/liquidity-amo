import { ethers } from "hardhat";

async function main() {
  const [admin] = await ethers.getSigners();
  const PriceManager = await ethers.getContractFactory("PriceManager");
  let priceContract = await PriceManager.deploy(admin, admin);
  await priceContract.waitForDeployment();
  let priceManagerAddress = await priceContract.getAddress();
  console.log("PriceManager contract:", priceManagerAddress);
}

// Execute the deployment
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
