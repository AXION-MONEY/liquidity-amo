import { ethers, upgrades } from "hardhat";

async function main() {
  const MuonClient = await ethers.getContractFactory("MuonClient");
  const validGateway = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const appId = "93307625660435442793252976666474786944683615644156490137714125190800568256860"; // "axion"
  const pubKey = ["0x4d116e81a9a511fb5fe12175050cdb4fab872afc2e291ba4ad9373468c9829be", "0"];
  const checkGatewaySignature = true;
  const muonClientContract = await MuonClient.deploy(validGateway, appId, pubKey, checkGatewaySignature);
  await muonClientContract.waitForDeployment();
  const muonClientAddress = await muonClientContract.getAddress();
  console.log("MuonClient contract:", muonClientAddress);

  const [admin] = await ethers.getSigners();
  const PriceManager = await ethers.getContractFactory("PriceManager");
  const priceContract = await upgrades.deployProxy(PriceManager, [admin.address, admin.address, muonClientAddress], {
    initializer: "initialize"
  });
  await priceContract.waitForDeployment();
  let priceManagerAddress = await priceContract.getAddress();
  console.log("PriceManager contract:", priceManagerAddress);
}

// Execute the deployment
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
