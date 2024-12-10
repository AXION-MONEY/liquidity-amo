import { ethers, upgrades } from "hardhat";

async function deployV2AMO(
  adminAddress: String,
  boostAddress: String,
  usdAddress: String,
  poolType: Number,
  minterAddress: String,
  factoryAddress: String,
  routerAddress: String,
  gaugeAddress: String,
  rewardVaultAddress: String,
  tokenId: Number,
  useTokenId: Boolean,
) {
  const boostMultiplier = ethers.parseUnits("1.1", 6);
  const validRangeWidth = ethers.parseUnits("0.01", 6);
  const validRemovingRatio = ethers.parseUnits("1.01", 6);
  const boostLowerPriceSell = ethers.parseUnits("0.99", 6);
  const boostUpperPriceBuy = ethers.parseUnits("1.01", 6);
  const boostSellRatio = ethers.parseUnits("0.8", 6);
  const usdBuyRatio = ethers.parseUnits("0.8", 6);

  const args = [
    adminAddress,
    boostAddress,
    usdAddress,
    poolType,
    minterAddress,
    factoryAddress,
    routerAddress,
    gaugeAddress,
    rewardVaultAddress,
    tokenId,
    useTokenId,
    boostMultiplier,
    validRangeWidth,
    validRemovingRatio,
    boostLowerPriceSell,
    boostUpperPriceBuy,
    boostSellRatio,
    usdBuyRatio,
  ];

  const V2AMO = await ethers.getContractFactory("V2AMO");
  console.log("Deploying V2AMO...");
  const amoContract = await upgrades.deployProxy(V2AMO, args, {
    initializer: "initialize",
  });
  await amoContract.waitForDeployment();
  console.log("V2AMO deployed to:", await amoContract.getAddress());
}

enum PoolType {
  SOLIDLY_V2,
  VELO_LIKE,
}

enum Chain {
  BASE = 8453,
  BNB = 56,
  FTM = 250,
  BLAST = 81457,
  OP = 10,
  ARB1 = 42161,
}

async function main() {
  const chains = {
    8453: {
      msigAddress: "",
      minterAddress: "",
    },
    56: {
      msigAddress: "",
      minterAddress: "",
    },
    250: {
      msigAddress: "",
      minterAddress: "",
    },
    81457: {
      msigAddress: "",
      minterAddress: "",
    },
    10: {
      msigAddress: "",
      minterAddress: "",
    },
    42161: {
      msigAddress: "",
      minterAddress: "",
    },
  };
  const dexes = {
    aerodrome: {
      chain: Chain.BASE,
      usdAddress: "",
      poolType: PoolType.VELO_LIKE,
      factoryAddress: "0x420DD381b31aEf6683db6B902084cB0FFECe40Da",
      routerAddress: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
      gaugeAddress: "",
      tokenId: 0,
      useTokenId: true,
    },
    equalizer: {
      chain: Chain.FTM,
      usdAddress: "",
      poolType: PoolType.SOLIDLY_V2,
      factoryAddress: "0xc6366EFD0AF1d09171fe0EBF32c7943BB310832a",
      routerAddress: "0x1A05EB736873485655F29a37DEf8a0AA87F5a447",
      gaugeAddress: "",
      tokenId: 0,
      useTokenId: false,
    },
    fenix: {
      chain: Chain.BLAST,
      usdAddress: "",
      poolType: PoolType.SOLIDLY_V2,
      factoryAddress: "0xa19C51D91891D3DF7C13Ed22a2f89d328A82950f",
      routerAddress: "0xbD571125856975DBfC2E9b6d1DE496D614D7BAEE",
      gaugeAddress: "",
      tokenId: 0,
      useTokenId: false,
    },
    ramses: {
      chain: Chain.ARB1,
      usdAddress: "",
      poolType: PoolType.SOLIDLY_V2,
      factoryAddress: "0xAAA20D08e59F6561f242b08513D36266C5A29415",
      routerAddress: "0xAAA87963EFeB6f7E0a2711F397663105Acb1805e",
      gaugeAddress: "",
      tokenId: 0,
      useTokenId: false,
    },
    solidly: {
      chain: Chain.FTM,
      usdAddress: "",
      poolType: PoolType.SOLIDLY_V2,
      factoryAddress: "0x777de5Fe8117cAAA7B44f396E93a401Cf5c9D4d6",
      routerAddress: "0x77784f96C936042A3ADB1dD29C91a55EB2A4219f",
      gaugeAddress: "",
      tokenId: 0,
      useTokenId: false,
    },
    thena: {
      chain: Chain.BNB,
      usdAddress: "",
      poolType: PoolType.SOLIDLY_V2,
      factoryAddress: "0xAFD89d21BdB66d00817d4153E055830B1c2B3970",
      routerAddress: "0xd4ae6eCA985340Dd434D38F470aCCce4DC78D109",
      gaugeAddress: "",
      tokenId: 0,
      useTokenId: false,
    },
    velodrome: {
      chain: Chain.OP,
      usdAddress: "",
      poolType: PoolType.VELO_LIKE,
      factoryAddress: "0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a",
      routerAddress: "0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858",
      gaugeAddress: "",
      tokenId: 0,
      useTokenId: true,
    },
  };

  const dexName = "aerodrome";
  const boostAddress = "0xBOO5...";
  const rewardVaultAddress = "VAULT-ADDRESS";

  const dex = dexes[dexName];
  const chain = chains[dex.chain];
  await deployV2AMO(
    chain.msigAddress,
    boostAddress,
    dex.usdAddress,
    dex.poolType,
    chain.minterAddress,
    dex.factoryAddress,
    dex.routerAddress,
    dex.gaugeAddress,
    rewardVaultAddress,
    dex.tokenId,
    dex.useTokenId,
  );
}

// Execute the deployment
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
