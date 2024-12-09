import { ethers, upgrades } from "hardhat";
import { IERC20Metadata } from "../typechain-types";

function getSqrtPriceX96(decimalsDiff: BigInt): BigInt {
  // decimalsDiff = token1Decimals - token0Decimals
  const unscaledPriceX96 = 1n << 96n;
  if (decimalsDiff < 0) return unscaledPriceX96 / 10n ** -decimalsDiff;
  else return unscaledPriceX96 * 10n ** decimalsDiff;
}

async function deployMinter(
  boostAddress: String,
  collateralAddress: String,
  treasuryAddress: String,
): Promise<String> {
  const Minter = await ethers.getContractFactory("Minter");
  console.log("Deploying Minter...");
  const contract = await upgrades.deployProxy(
    Minter,
    [boostAddress, boostAddress, treasuryAddress],
    { initializer: "initialize" },
  );
  await contract.waitForDeployment();
  const minterAddress = await contract.getAddress();
  console.log("Minter deployed to:", minterAddress);
  return minterAddress;
}

async function deployBoostToken(adminAddress: String): Promise<String> {
  const BoostStablecoin = await ethers.getContractFactory("BoostStablecoin");
  console.log("Deploying BoostStablecoin...");
  const contract = await upgrades.deployProxy(BoostStablecoin, [adminAddress], {
    initializer: "initialize",
  });
  await contract.waitForDeployment();
  const boostAddress = await contract.getAddress();
  console.log("BoostStablecoin deployed to:", boostAddress);
  return boostAddress;
}

async function deployV3AMO(
  adminAddress: String,
  boostAddress: String,
  usdAddress: String,
  poolAddress: String,
  poolType: Number,
  quoterAddress: String,
  poolCustomDeployerAddress: String,
  minterAddress: String,
) {
  const boostDecimals = 18n;
  const MIN_TICK = -887272;
  const MAX_TICK = -MIN_TICK;

  // full range
  const tickLower = MIN_TICK;
  const tickUpper = MAX_TICK;

  const usdContract = (await ethers.getContractAt(
    "IERC20Metadata",
    usdAddress,
  )) as unknown as IERC20Metadata;
  const usdDecimals = await usdContract.decimals();

  let decimalsDiff;
  if (boostAddress.toLowerCase() < usdAddress.toLowerCase())
    decimalsDiff = usdDecimals - boostDecimals;
  else decimalsDiff = boostDecimals - usdDecimals;
  const targetSqrtPriceX96 = getSqrtPriceX96(decimalsDiff);
  console.log("targetSqrtPriceX96:", targetSqrtPriceX96);

  const boostMultiplier = ethers.parseUnits("1.1", 6);
  const validRangeWidth = ethers.parseUnits("0.01", 6);
  const validRemovingRatio = ethers.parseUnits("1.01", 6);
  const usdUsageRatio = ethers.parseUnits("0.95", 6);
  const boostLowerPriceSell = ethers.parseUnits("0.99", 6);
  const boostUpperPriceBuy = ethers.parseUnits("1.01", 6);

  const args = [
    adminAddress,
    boostAddress,
    usdAddress,
    poolAddress,
    poolType,
    quoterAddress,
    poolCustomDeployerAddress,
    minterAddress,
    tickLower,
    tickUpper,
    targetSqrtPriceX96,
    boostMultiplier,
    validRangeWidth,
    validRemovingRatio,
    usdUsageRatio,
    boostLowerPriceSell,
    boostUpperPriceBuy,
  ];

  const V3AMO = await ethers.getContractFactory("V3AMO");
  console.log("Deploying V3AMO...");
  const amoContract = await upgrades.deployProxy(V3AMO, args, {
    initializer: "initialize",
  });
  await amoContract.waitForDeployment();
  console.log("V3AMO deployed to:", await amoContract.getAddress());
}

enum PoolType {
  SOLIDLY_V3,
  CL,
  ALGEBRA_V1_0,
  ALGEBRA_V1_9,
  ALGEBRA_INTEGRAL,
  RAMSES_V2,
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
      poolAddress: "",
      poolType: PoolType.CL,
      quoterAddress: "0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0",
      poolCustomDeployerAddress: ethers.ZeroAddress,
    },
    camelot: {
      chain: Chain.ARB1,
      usdAddress: "",
      poolAddress: "",
      poolType: PoolType.ALGEBRA_V1_9,
      quoterAddress: "0x0Fc73040b26E9bC8514fA028D998E73A254Fa76E",
      poolCustomDeployerAddress: ethers.ZeroAddress,
    },
    fenix: {
      chain: Chain.BLAST,
      usdAddress: "",
      poolAddress: "",
      poolType: PoolType.ALGEBRA_INTEGRAL,
      quoterAddress: "0x94Ca5B835186A37A99776780BF976fAB81D84ED8",
      poolCustomDeployerAddress: ethers.ZeroAddress,
    },
    ramses: {
      chain: Chain.ARB1,
      usdAddress: "",
      poolAddress: "",
      poolType: PoolType.RAMSES_V2,
      quoterAddress: "0xAA20EFF7ad2F523590dE6c04918DaAE0904E3b20",
      poolCustomDeployerAddress: ethers.ZeroAddress,
    },
    solidly: {
      chain: Chain.FTM,
      usdAddress: "",
      poolAddress: "",
      poolType: PoolType.SOLIDLY_V3,
      quoterAddress: ethers.ZeroAddress,
      poolCustomDeployerAddress: ethers.ZeroAddress,
    },
    thena: {
      chain: Chain.BNB,
      usdAddress: "",
      poolAddress: "",
      poolType: PoolType.ALGEBRA_V1_0,
      quoterAddress: "0xeA68020D6A9532EeC42D4dB0f92B83580c39b2cA",
      poolCustomDeployerAddress: ethers.ZeroAddress,
    },
    velodrome: {
      chain: Chain.OP,
      usdAddress: "",
      poolAddress: "",
      poolType: PoolType.CL,
      quoterAddress: "0x89D8218ed5fF1e46d8dcd33fb0bbeE3be1621466",
      poolCustomDeployerAddress: ethers.ZeroAddress,
    },
  };

  const dexName = "aerodrome";
  const boostAddress = "0xBOO5...";

  const dex = dexes[dexName];
  const chain = chains[dex.chain];
  await deployV3AMO(
    chain.msigAddress,
    boostAddress,
    dex.usdAddress,
    dex.poolAddress,
    dex.poolType,
    dex.quoterAddress,
    dex.poolCustomDeployerAddress,
    chain.minterAddress,
  );
}

// Execute the deployment
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
