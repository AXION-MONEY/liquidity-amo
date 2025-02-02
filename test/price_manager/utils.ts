import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { BoostStablecoin, ICLPool, Minter, MockERC20, PriceManager, V2AMO, V3AMO } from "../../typechain-types";

export async function deployBaseContracts(
  admin: SignerWithAddress,
  user: SignerWithAddress,
  initAmount: bigint
): Promise<[BoostStablecoin, MockERC20, Minter]> {
  const BoostFactory = await ethers.getContractFactory("BoostStablecoin");
  const boost = await upgrades.deployProxy(BoostFactory, [admin.address]);
  await boost.waitForDeployment();
  const boostAddress = await boost.getAddress();

  const MockErc20Factory = await ethers.getContractFactory("MockERC20");
  const testUsd = await MockErc20Factory.deploy("USD", "USD", 18);
  await testUsd.waitForDeployment();
  const usdAddress = await testUsd.getAddress();

  const MinterFactory = await ethers.getContractFactory("Minter");
  const minter = await upgrades.deployProxy(MinterFactory, [boostAddress, usdAddress, admin.address]);
  await minter.waitForDeployment();
  const minterAddress = await minter.getAddress();

  const MINTER_ROLE = await boost.MINTER_ROLE();

  await boost.grantRole(MINTER_ROLE, minterAddress);
  await boost.grantRole(MINTER_ROLE, admin.address);
  await boost.connect(admin).mint(admin.address, initAmount);
  await boost.connect(admin).mint(user.address, initAmount);
  await testUsd.connect(admin).mint(admin.address, initAmount);
  await testUsd.connect(admin).mint(user.address, initAmount);

  return [boost, testUsd, minter];
}

export async function deployPriceManager(admin: SignerWithAddress): Promise<PriceManager> {
  const MuonClientFactory = await ethers.getContractFactory("MockMuonClient");
  const muonClient = await MuonClientFactory.deploy();
  await muonClient.waitForDeployment();
  const muonClientAddress = await muonClient.getAddress();

  const PriceManagerFactory = await ethers.getContractFactory("PriceManager");
  const priceManager = await upgrades.deployProxy(
    PriceManagerFactory,
    [admin.address, admin.address, muonClientAddress],
    {
      initializer: "initialize"
    }
  );
  await priceManager.waitForDeployment();

  return priceManager;
}

export async function deployV2AMO(
  admin: SignerWithAddress,
  boostAddress: string,
  usdAddress: string,
  poolFee: bigint,
  minterAddress: string,
  priceManagerAddress: string,
  pairedTokenType: number,
  routerAddress: string,
  boostMultiplier: bigint,
  validRangeWidth: bigint,
  validRemovingRatio: bigint,
  boostLowerPriceSell: bigint,
  boostUpperPriceBuy: bigint,
  boostSellRatio: bigint,
  usdBuyRatio: bigint
): Promise<V2AMO> {
  const GaugeFactory = await ethers.getContractFactory("MockGauge");
  const gauge = await GaugeFactory.deploy();
  await gauge.waitForDeployment();
  const gaugeAddress = await gauge.getAddress();
  const args = [
    admin.address,
    boostAddress,
    usdAddress,
    false, // stable
    poolFee,
    1, // VELO_LIKE
    minterAddress,
    priceManagerAddress,
    pairedTokenType,
    ethers.ZeroAddress,
    routerAddress,
    gaugeAddress,
    admin.address, // rewardVault
    0, // tokenId
    false, // useTokenId
    boostMultiplier,
    validRangeWidth,
    validRemovingRatio,
    boostLowerPriceSell,
    boostUpperPriceBuy,
    boostSellRatio,
    usdBuyRatio
  ];
  const V2AMOFactory = await ethers.getContractFactory("V2AMO");
  const amo = await upgrades.deployProxy(V2AMOFactory, args, {
    initializer:
      "initialize(address,address,address,bool,uint256,uint8,address,address,uint8,address,address,address,address,uint256,bool,uint256,uint24,uint24,uint256,uint256,uint256,uint256)"
  });
  await amo.waitForDeployment();
  return amo;
}

export async function deployV3AMO(
  admin: SignerWithAddress,
  boostAddress: string,
  usdAddress: string,
  poolAddress: string,
  quoterAddress: string,
  minterAddress: string,
  priceManagerAddress: string,
  pairedTokenType: number,
  tickLower: number,
  tickUpper: number,
  boostMultiplier: bigint,
  validRangeWidth: bigint,
  validRemovingRatio: bigint,
  boostLowerPriceSell: bigint,
  boostUpperPriceBuy: bigint
): Promise<V3AMO> {
  const args = [
    admin.address,
    boostAddress,
    usdAddress,
    poolAddress,
    1, // PoolType.CL
    quoterAddress,
    ethers.ZeroAddress, // poolCustomDeployer
    minterAddress,
    priceManagerAddress,
    pairedTokenType,
    tickLower,
    tickUpper,
    boostMultiplier,
    validRangeWidth,
    validRemovingRatio,
    boostLowerPriceSell,
    boostUpperPriceBuy
  ];
  const V3AMOFactory = await ethers.getContractFactory("V3AMO");
  const amo = await upgrades.deployProxy(V3AMOFactory, args, {
    initializer:
      "initialize(address,address,address,address,uint8,address,address,address,address,uint8,int24,int24,uint256,uint24,uint24,uint256,uint256)"
  });
  await amo.waitForDeployment();
  const AMO_ROLE = await amo.AMO_ROLE();
  await amo.connect(admin).grantRole(AMO_ROLE, admin.address);
  return amo;
}

export async function createCLPool(factoryAddress: string, boostAddress: string, usdAddress: string): Promise<ICLPool> {
  const tickSpacing = 1;
  const price = "1";
  const poolFactory = await ethers.getContractAt("ICLFactory", factoryAddress);
  let sqrtPriceX96 = BigInt(
    Math.floor(Math.sqrt(Number((ethers.parseUnits(price, 6) * BigInt(2 ** 192)) / BigInt(10 ** 6))))
  );
  await poolFactory.createPool(boostAddress, usdAddress, tickSpacing, sqrtPriceX96);
  const poolAddress = await poolFactory.getPool(boostAddress, usdAddress, tickSpacing);
  return await ethers.getContractAt("ICLPool", poolAddress);
}

export async function addV2Liquidity(
  admin: SignerWithAddress,
  routerAddress: string,
  boost: BoostStablecoin,
  usd: MockERC20,
  amoAddress: string,
  amount: bigint
) {
  const router = await ethers.getContractAt("IVRouter", routerAddress);
  await boost.connect(admin).approve(routerAddress, amount);
  await usd.connect(admin).approve(routerAddress, amount);
  await router.connect(admin).addLiquidity(
    await boost.getAddress(),
    await usd.getAddress(),
    false, // stable
    amount,
    amount,
    0, // min amounts = 0 for testing
    0,
    amoAddress,
    ethers.MaxUint256
  );
}

export async function v3Swap(
  user: SignerWithAddress,
  token0: MockERC20 | BoostStablecoin,
  token1: MockERC20 | BoostStablecoin,
  routerAddress: string,
  amount: bigint
) {
  if (amount == 0n) return;
  if (amount < 0n) {
    amount = -amount;
    [token0, token1] = [token1, token0];
  }
  const deadline = Math.floor(Date.now() / 1000) + 60 * 100;
  const router = await ethers.getContractAt("ISwapRouter", routerAddress);
  const MIN_SQRT_RATIO = BigInt("4295128739") + BigInt(1);
  const MAX_SQRT_RATIO = BigInt("1461446703485210103287273052203988822378723970342") - BigInt(1);
  await token0.connect(user).approve(routerAddress, amount);
  await token1.connect(user).approve(routerAddress, amount);
  const tokenIn = await token0.getAddress();
  const tokenOut = await token1.getAddress();
  const sqrtPriceLimitX96 = tokenIn.toLowerCase() < tokenOut.toLowerCase() ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;
  const params = {
    tokenIn: tokenIn,
    tokenOut: tokenOut,
    tickSpacing: 1,
    recipient: user.address,
    deadline: deadline,
    amountIn: amount,
    amountOutMinimum: 0,
    sqrtPriceLimitX96: sqrtPriceLimitX96
  };
  await router.connect(user).exactInputSingle(params);
}

export async function v2Swap(
  user: SignerWithAddress,
  token0: MockERC20 | BoostStablecoin,
  token1: MockERC20 | BoostStablecoin,
  routerAddress: string,
  amount: bigint
) {
  if (amount == 0n) return;
  if (amount < 0n) {
    amount = -amount;
    [token0, token1] = [token1, token0];
  }
  const deadline = Math.floor(Date.now() / 1000) + 60 * 100;
  const router = await ethers.getContractAt("IVRouter", routerAddress);
  const route = [
    {
      from: await token0.getAddress(),
      to: await token1.getAddress(),
      stable: false,
      factory: ethers.ZeroAddress
    }
  ];
  await token0.connect(user).approve(routerAddress, amount);
  await token1.connect(user).approve(routerAddress, amount);
  await router.connect(user).swapExactTokensForTokens(amount, 0, route, user.address, deadline);
}

export async function getTargetPrice(amo: V2AMO | V3AMO, log: boolean = false): Promise<bigint> {
  const tp = await amo.targetPrice();
  if (log) console.log("Target Price: ", Number(tp) / 1e6);
  return tp;
}

export async function getCurrentPrice(amo: V2AMO | V3AMO, log: boolean = false): Promise<bigint> {
  const cp = await amo.boostPrice();
  if (log) console.log("Current Price:", Number(cp) / 1e6);
  return cp;
}

export async function logPriceDiff(amo: V2AMO | V3AMO, indents: number = 1): Promise<{ tp: bigint; cp: bigint }> {
  const tp = await amo.targetPrice();
  const cp = await amo.boostPrice();
  let diff;
  let word;
  if (cp > tp) {
    diff = Number(cp - tp);
    word = "above";
  } else {
    diff = Number(tp - cp);
    word = "below";
  }
  console.log(`${"\t".repeat(indents)}Price is ${((diff / Number(tp)) * 100).toFixed(2)}% ${word}`);
  return { tp, cp };
}
