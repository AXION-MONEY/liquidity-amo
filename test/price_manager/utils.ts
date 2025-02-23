import { ethers, network, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { nearestUsableTick, TickMath, priceToClosestTick } from "@uniswap/v3-sdk";
import { Price, Token } from "@uniswap/sdk-core";
import {
  BoostStablecoin,
  ICLPool,
  Minter,
  MockERC20,
  PriceManager,
  V2AMO,
  V3AMO,
  IRamsesV2Pool,
  MockUniswapV3PoolCaller
} from "../../typechain-types";

const sigs = {
  susde: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress
      },
      gatewaySignature: ethers.ZeroHash,
      token: "susde"
    },
    states: {
      totalSupply: "3734814116804093597606146132",
      balance: "4304104583370657539163990168",
      lastDistributionTimestamp: "1738207835",
      vestingAmount: "460055794761904761904761"
    }
  },
  sfrax: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress
      },
      gatewaySignature: ethers.ZeroHash,
      token: "sfrax"
    },
    states: {
      totalSupply: "71228619772829715106592883",
      storedTotalAssets: "79039466004482887067661211",
      rewardsCycleData: {
        cycleEnd: "1738800000",
        lastSync: "1738195271",
        rewardCycleAmount: "578157898242524520561322"
      },
      lastRewardsDistribution: "1738219139",
      maxDistributionPerSecondPerAsset: "3329556719"
    }
  },
  sdai: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress
      },
      gatewaySignature: ethers.ZeroHash,
      token: "sdai"
    },
    states: {
      dsr: "1000000003380572527855758393",
      chi: "1141443554266986624494275064",
      rho: "1738222919"
    }
  }
};

export enum PairedTokenType {
  STABLE,
  SUSDE,
  SFRAX,
  SDAI
}

export enum PoolType {
  SOLIDLY_V3,
  CL, // Aerodrome, Velodrome
  ALGEBRA_V1_0,
  ALGEBRA_V1_9,
  ALGEBRA_INTEGRAL,
  RAMSES_V2
}

export async function initNetwork(
  jsonRpcUrl: string,
  blockNumber?: number
): Promise<[SignerWithAddress, SignerWithAddress, PriceManager]> {
  const [admin, user] = await ethers.getSigners();
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: jsonRpcUrl,
          blockNumber: blockNumber
        }
      }
    ]
  });
  const priceManager = await deployPriceManager(admin);
  await priceManager.connect(user).setSUsdeWithSig(sigs.susde.states, sigs.susde.muonSig);
  await priceManager.connect(user).setSFraxWithSig(sigs.sfrax.states, sigs.sfrax.muonSig);
  await priceManager.connect(user).setPotWithSig(sigs.sdai.states, sigs.sdai.muonSig);
  return [admin, user, priceManager];
}

export function pairedTokenTypeName(pairedTokenType: PairedTokenType): string {
  switch (pairedTokenType) {
    case PairedTokenType.STABLE:
      return "STABLE";
    case PairedTokenType.SUSDE:
      return "SUSDE";
    case PairedTokenType.SFRAX:
      return "SFRAX";
    case PairedTokenType.SDAI:
      return "SDAI";
    default:
      throw new Error("Invalid pairedTokenType");
  }
}

export async function getInitPrice(priceManager: PriceManager, pairedTokenType: PairedTokenType): Promise<bigint> {
  const ONE = BigInt(10 ** 6);
  switch (pairedTokenType) {
    case PairedTokenType.STABLE:
      return ONE;
    case PairedTokenType.SUSDE:
      return await priceManager.sUsdePreviewDeposit(ONE);
    case PairedTokenType.SFRAX:
      return await priceManager.sFraxPreviewDeposit(ONE);
    case PairedTokenType.SDAI:
      return await priceManager.sDaiPreviewDeposit(ONE);
    default:
      throw new Error("Invalid pairedTokenType");
  }
}

export async function getTickBounds(
  boost: BoostStablecoin,
  usd: MockERC20,
  tickSpacing: number,
  lowerPriceValue?: string,
  upperPriceValue?: string
): Promise<{ tickLower: number; tickUpper: number }> {
  let boostToken = new Token(0, await boost.getAddress(), Number(await boost.decimals()));
  let usdToken = new Token(0, await usd.getAddress(), Number(await usd.decimals()));
  let lowerTick, upperTick;
  if (lowerPriceValue !== undefined) {
    const lowerPrice = new Price(
      boostToken,
      usdToken,
      Number(ethers.parseUnits("1", boostToken.decimals)),
      Number(ethers.parseUnits(lowerPriceValue, usdToken.decimals))
    );
    console.log("Lower Price:", lowerPrice.toFixed());
    lowerTick = priceToClosestTick(lowerPrice);
  } else {
    console.log("Lower Price: -inf");
    lowerTick = TickMath.MIN_TICK;
  }
  if (upperPriceValue !== undefined) {
    const upperPrice = new Price(
      boostToken,
      usdToken,
      Number(ethers.parseUnits("1", boostToken.decimals)),
      Number(ethers.parseUnits(upperPriceValue, usdToken.decimals))
    );
    console.log("Upper Price:", upperPrice.toFixed());
    upperTick = priceToClosestTick(upperPrice);
  } else {
    console.log("Upper Price: +inf");
    upperTick = TickMath.MAX_TICK;
  }
  let tickLower = nearestUsableTick(lowerTick, tickSpacing);
  let tickUpper = nearestUsableTick(upperTick, tickSpacing);
  if (tickUpper < tickLower) [tickLower, tickUpper] = [tickUpper, tickLower];
  return { tickLower, tickUpper };
}

export async function deployBaseContracts(
  admin: SignerWithAddress,
  user: SignerWithAddress,
  usdDecimals: number,
  initAmount: string
): Promise<[BoostStablecoin, MockERC20, Minter]> {
  const BoostFactory = await ethers.getContractFactory("BoostStablecoin");
  const boost = await upgrades.deployProxy(BoostFactory, [admin.address]);
  await boost.waitForDeployment();
  const boostAddress = await boost.getAddress();

  const MockErc20Factory = await ethers.getContractFactory("MockERC20");
  const usd = await MockErc20Factory.deploy("USD", "USD", usdDecimals);
  await usd.waitForDeployment();
  const usdAddress = await usd.getAddress();

  const MinterFactory = await ethers.getContractFactory("Minter");
  const minter = await upgrades.deployProxy(MinterFactory, [boostAddress, usdAddress, admin.address]);
  await minter.waitForDeployment();
  const minterAddress = await minter.getAddress();

  const MINTER_ROLE = await boost.MINTER_ROLE();

  await boost.grantRole(MINTER_ROLE, minterAddress);
  await boost.grantRole(MINTER_ROLE, admin.address);
  await boost.connect(admin).mint(admin.address, ethers.parseUnits(initAmount, 18));
  await boost.connect(admin).mint(user.address, ethers.parseUnits(initAmount, 18));
  await usd.connect(admin).mint(admin.address, ethers.parseUnits(initAmount, usdDecimals));
  await usd.connect(admin).mint(user.address, ethers.parseUnits(initAmount, usdDecimals));

  return [boost, usd, minter];
}

export async function deployPriceManager(admin: SignerWithAddress): Promise<PriceManager> {
  const MuonClientFactory = await ethers.getContractFactory("MockMuonClient");
  const muonClient = await MuonClientFactory.deploy();
  await muonClient.waitForDeployment();
  const muonClientAddress = await muonClient.getAddress();

  const PriceManagerFactory = await ethers.getContractFactory("PriceManager");
  const priceManager = await upgrades.deployProxy(
    PriceManagerFactory,
    [admin.address, admin.address, admin.address, muonClientAddress],
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
  poolType: PoolType,
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
    poolType,
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

async function _beforeCreatePool(
  boost: BoostStablecoin,
  usd: MockERC20,
  price: bigint
): Promise<[string, string, bigint]> {
  const boostAddress = await boost.getAddress();
  const boostDecimals = await boost.decimals();
  const usdAddress = await usd.getAddress();
  const usdDecimals = await usd.decimals();
  if (usdAddress.toLowerCase() < boostAddress.toLowerCase()) price = BigInt(10 ** 12) / price;
  let priceX96 = Number((price * BigInt(2 ** 192)) / BigInt(10 ** 6));
  const decimalsDiff = Number(boostDecimals - usdDecimals);
  if (boostAddress.toLowerCase() < usdAddress.toLowerCase()) priceX96 /= 10 ** decimalsDiff;
  else priceX96 *= 10 ** decimalsDiff;
  let sqrtPriceX96 = BigInt(Math.floor(Math.sqrt(priceX96)));
  return [boostAddress, usdAddress, sqrtPriceX96];
}

export async function createCLPool(
  factoryAddress: string,
  boost: BoostStablecoin,
  usd: MockERC20,
  price: bigint,
  tickSpacing: number
): Promise<ICLPool> {
  const [boostAddress, usdAddress, sqrtPriceX96] = await _beforeCreatePool(boost, usd, price);
  const poolFactory = await ethers.getContractAt("ICLFactory", factoryAddress);
  await poolFactory.createPool(boostAddress, usdAddress, tickSpacing, sqrtPriceX96);
  const poolAddress = await poolFactory.getPool(boostAddress, usdAddress, tickSpacing);
  return await ethers.getContractAt("ICLPool", poolAddress);
}

export async function createRamsesPool(
  factoryAddress: string,
  boost: BoostStablecoin,
  usd: MockERC20,
  price: bigint,
  fee: number
): Promise<IRamsesV2Pool> {
  const [boostAddress, usdAddress, sqrtPriceX96] = await _beforeCreatePool(boost, usd, price);
  const poolFactory = await ethers.getContractAt("IRamsesV2Factory", factoryAddress);
  await poolFactory.createPool(boostAddress, usdAddress, fee);
  const poolAddress = await poolFactory.getPool(boostAddress, usdAddress, fee);
  const pool = await ethers.getContractAt("IRamsesV2Pool", poolAddress);
  await pool.initialize(sqrtPriceX96);
  return pool;
}

export async function addV2Liquidity(
  admin: SignerWithAddress,
  routerAddress: string,
  boost: BoostStablecoin,
  usd: MockERC20,
  amoAddress: string,
  amount: string,
  price: bigint = ethers.parseUnits("1", 6)
) {
  const router = await ethers.getContractAt("IVRouter", routerAddress);
  const boostAmount = ethers.parseUnits(amount, 18);
  let usdAmount = ethers.parseUnits(amount, await usd.decimals());
  usdAmount = (usdAmount * price) / BigInt(10 ** 6);
  await boost.connect(admin).approve(routerAddress, boostAmount);
  await usd.connect(admin).approve(routerAddress, usdAmount);
  await router.connect(admin).addLiquidity(
    await boost.getAddress(),
    await usd.getAddress(),
    false, // stable
    boostAmount,
    usdAmount,
    0, // min amounts = 0 for testing
    0,
    amoAddress,
    ethers.MaxUint256
  );
}

export async function v3Swap(
  user: SignerWithAddress,
  poolCaller: MockUniswapV3PoolCaller,
  token0: MockERC20 | BoostStablecoin,
  token1: MockERC20 | BoostStablecoin,
  swapAmount: string
) {
  let _swapAmount = Number(swapAmount);
  if (_swapAmount == 0) return;
  if (_swapAmount < 0) {
    _swapAmount = -_swapAmount;
    [token0, token1] = [token1, token0];
  }
  const amount = ethers.parseUnits(_swapAmount.toString(), await token0.decimals());
  const MIN_SQRT_RATIO = BigInt("4295128739") + BigInt(1);
  const MAX_SQRT_RATIO = BigInt("1461446703485210103287273052203988822378723970342") - BigInt(1);
  await token0.connect(user).approve(await poolCaller.getAddress(), amount);
  const tokenIn = await token0.getAddress();
  const tokenOut = await token1.getAddress();
  const zeroForOne = tokenIn.toLowerCase() < tokenOut.toLowerCase();
  const sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;
  await poolCaller.connect(user).swap(user.address, zeroForOne, amount, sqrtPriceLimitX96);
}

export async function v2Swap(
  user: SignerWithAddress,
  token0: MockERC20 | BoostStablecoin,
  token1: MockERC20 | BoostStablecoin,
  routerAddress: string,
  swapAmount: string
) {
  let _swapAmount = Number(swapAmount);
  if (_swapAmount == 0) return;
  if (_swapAmount < 0) {
    _swapAmount = -_swapAmount;
    [token0, token1] = [token1, token0];
  }
  const amount = ethers.parseUnits(_swapAmount.toString(), await token0.decimals());
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

export async function logPriceDiff(amo: V2AMO | V3AMO, indents: number = 2): Promise<{ tp: bigint; cp: bigint }> {
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

export function getTestCaseTitle(swapAmount: string, ubb: boolean = false): string {
  let executeWord = "above";
  let revertWord = "below";
  if (ubb) [executeWord, revertWord] = [revertWord, executeWord];
  if (Number(swapAmount) > 0) return `execute when the price is ${executeWord} the target price (${swapAmount})`;
  else if (Number(swapAmount) < 0) return `revert when the price is ${revertWord} the target price (${swapAmount})`;
  else return "revert when the price is already in range";
}
