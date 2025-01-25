import { ethers } from "hardhat";

async function main() {
  const MuonClient = await ethers.getContractFactory("MuonClient");
  const validGateway = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const appId = "38817632187816630511872077327276950283036755817485108094337570240411227542969";
  const pubKey = ["0x4d116e81a9a511fb5fe12175050cdb4fab872afc2e291ba4ad9373468c9829be", "0"];
  const checkGatewaySignature = true;
  let contract = await MuonClient.deploy(validGateway, appId, pubKey, checkGatewaySignature);
  await contract.waitForDeployment();
  console.log("MuonClient contract:", await contract.getAddress());
}

// Execute the deployment
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
