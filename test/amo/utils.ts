import { ethers, network, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { nearestUsableTick, TickMath, priceToClosestTick } from "@uniswap/v3-sdk";
import { Price, Token } from "@uniswap/sdk-core";
import { Minter, MockERC20, PriceManager, V2AMO, V3AMO, MockUniswapV3PoolCaller, Ion } from "../../typechain-types";
import { time } from "@nomicfoundation/hardhat-network-helpers";

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

export enum PairTokenType {
  STABLE,
  SUSDE,
  SFRAX,
  SDAI
}

export enum V3PoolType {
  SOLIDLY_V3,
  CL, // Aerodrome, Velodrome
  ALGEBRA_V1,
  ALGEBRA_INTEGRAL,
  RAMSES_V2
}

export enum V2PoolType {
  SOLIDLY_V2,
  VELO_LIKE // Aerodrome, Velodrome
}

function numberToAddress(n: number): string {
  const hex = n.toString(16);
  const padded = hex.padStart(40, "0");
  return `0x${padded}`;
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
  const priceOne = ethers.parseUnits("1", 6);
  const timestamp = await time.latest();
  await priceManager.connect(admin).setStable(numberToAddress(PairTokenType.SUSDE), priceOne, timestamp);
  await priceManager.connect(admin).setStable(numberToAddress(PairTokenType.SFRAX), priceOne, timestamp);
  await priceManager.connect(admin).setStable(numberToAddress(PairTokenType.SDAI), priceOne, timestamp);
  return [admin, user, priceManager];
}

export function pairedTokenTypeName(pairedTokenType: PairTokenType): string {
  switch (pairedTokenType) {
    case PairTokenType.STABLE:
      return "STABLE";
    case PairTokenType.SUSDE:
      return "SUSDE";
    case PairTokenType.SFRAX:
      return "SFRAX";
    case PairTokenType.SDAI:
      return "SDAI";
    default:
      throw new Error("Invalid pairedTokenType");
  }
}

export async function getInitPrice(priceManager: PriceManager, pairedTokenType: PairTokenType): Promise<bigint> {
  const ONE = BigInt(10 ** 6);
  switch (pairedTokenType) {
    case PairTokenType.STABLE:
      return ONE;
    case PairTokenType.SUSDE:
      return await priceManager.sUsdePreviewDeposit(ONE);
    case PairTokenType.SFRAX:
      return await priceManager.sFraxPreviewDeposit(ONE);
    case PairTokenType.SDAI:
      return await priceManager.sDaiPreviewDeposit(ONE);
    default:
      throw new Error("Invalid pairedTokenType");
  }
}

export async function getTickBounds(
  ion: Ion,
  pairToken: MockERC20,
  tickSpacing: number,
  lowerPriceValue?: string,
  upperPriceValue?: string
): Promise<{ tickLower: number; tickUpper: number }> {
  let ionToken = new Token(0, await ion.getAddress(), Number(await ion.decimals()));
  let pairTokenToken = new Token(0, await pairToken.getAddress(), Number(await pairToken.decimals()));
  let lowerTick, upperTick;
  if (lowerPriceValue !== undefined) {
    const lowerPrice = new Price(
      ionToken,
      pairTokenToken,
      Number(ethers.parseUnits("1", ionToken.decimals)),
      Number(ethers.parseUnits(lowerPriceValue, pairTokenToken.decimals))
    );
    // console.log("Lower Price:", lowerPrice.toFixed());
    lowerTick = priceToClosestTick(lowerPrice);
  } else {
    // console.log("Lower Price: -inf");
    lowerTick = TickMath.MIN_TICK;
  }
  if (upperPriceValue !== undefined) {
    const upperPrice = new Price(
      ionToken,
      pairTokenToken,
      Number(ethers.parseUnits("1", ionToken.decimals)),
      Number(ethers.parseUnits(upperPriceValue, pairTokenToken.decimals))
    );
    // console.log("Upper Price:", upperPrice.toFixed());
    upperTick = priceToClosestTick(upperPrice);
  } else {
    // console.log("Upper Price: +inf");
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
  pairTokenDecimals: number,
  initAmount: string
): Promise<[Ion, MockERC20, Minter]> {
  const IonFactory = await ethers.getContractFactory("Ion");
  const ion = await upgrades.deployProxy(IonFactory, ["Ion Stablecoin", "ION", admin.address]);
  await ion.waitForDeployment();
  const ionAddress = await ion.getAddress();

  const MockErc20Factory = await ethers.getContractFactory("MockERC20");
  const pairToken = await MockErc20Factory.deploy("USD", "USD", pairTokenDecimals);
  await pairToken.waitForDeployment();
  const pairTokenAddress = await pairToken.getAddress();

  const MinterFactory = await ethers.getContractFactory("Minter");
  const minter = await upgrades.deployProxy(MinterFactory, [ionAddress, pairTokenAddress, admin.address]);
  await minter.waitForDeployment();
  const minterAddress = await minter.getAddress();

  const MINTER_ROLE = await ion.MINTER_ROLE();

  await ion.grantRole(MINTER_ROLE, minterAddress);
  await ion.grantRole(MINTER_ROLE, admin.address);
  await ion.connect(admin).mint(admin.address, ethers.parseUnits(initAmount, 18));
  await ion.connect(admin).mint(user.address, ethers.parseUnits(initAmount, 18));
  await pairToken.connect(admin).mint(admin.address, ethers.parseUnits(initAmount, pairTokenDecimals));
  await pairToken.connect(admin).mint(user.address, ethers.parseUnits(initAmount, pairTokenDecimals));

  return [ion, pairToken, minter];
}

export async function deployPriceManager(admin: SignerWithAddress): Promise<PriceManager> {
  const MuonClientFactory = await ethers.getContractFactory("MockMuonClient");
  const muonClient = await MuonClientFactory.deploy();
  await muonClient.waitForDeployment();
  const muonClientAddress = await muonClient.getAddress();
  const stablePriceLower = ethers.parseUnits("0.5", 6);
  const stablePriceUpper = ethers.parseUnits("2.0", 6);

  const PriceManagerFactory = await ethers.getContractFactory("PriceManager");
  const priceManager = await upgrades.deployProxy(
    PriceManagerFactory,
    [admin.address, admin.address, admin.address, muonClientAddress, stablePriceLower, stablePriceUpper],
    {
      initializer: "initialize"
    }
  );
  await priceManager.waitForDeployment();

  return priceManager;
}

export async function deployV2AMO(
  admin: SignerWithAddress,
  ionAddress: string,
  pairTokenAddress: string,
  poolType: V2PoolType,
  minterAddress: string,
  priceManagerAddress: string,
  pairedTokenType: number,
  routerAddress: string,
  validRangeWidth: bigint,
  sellRatio: bigint,
  buyRatio: bigint,
  sellIonRatioLimit: bigint = ethers.parseUnits("10", 6),
  removeLiquidityRatioLimit: bigint = ethers.parseUnits("1", 6),
  periodDuration: bigint = 1n,
  feeDivider: bigint = BigInt(10 ** 4),
  isSolidly: boolean = false
): Promise<V2AMO> {
  if (pairedTokenType === PairTokenType.STABLE) {
    const priceManager = await ethers.getContractAt("PriceManager", priceManagerAddress);
    const timestamp = await time.latest();
    await priceManager.connect(admin).setStable(pairTokenAddress, ethers.parseUnits("1", 6), timestamp);
  }
  const stable = false;
  let poolAddress: string;
  let factoryAddress: string;
  let poolFee: bigint;
  if (poolType === V2PoolType.SOLIDLY_V2) {
    const router = await ethers.getContractAt("ISolidlyRouter", routerAddress);
    factoryAddress = await router.factory();
    const factory = await ethers.getContractAt("IPairFactory", factoryAddress);
    if ((await router.pairFor(ionAddress, pairTokenAddress, stable)) === ethers.ZeroAddress) {
      await factory.createPair(ionAddress, pairTokenAddress, stable);
    }
    if (isSolidly) {
      const factory = await ethers.getContractAt("IPairFactory", factoryAddress);
      poolFee = stable ? await factory.stableFees() : await factory.volatileFees();
    } else {
      poolFee = await factory.getFee(stable);
    }
    poolAddress = await router.pairFor(ionAddress, pairTokenAddress, stable);
  } else {
    const router = await ethers.getContractAt("IVRouter", routerAddress);
    factoryAddress = await router.defaultFactory();
    poolAddress = await router.poolFor(pairTokenAddress, ionAddress, stable, factoryAddress);
    const factory = await ethers.getContractAt("IPoolFactory", factoryAddress);
    poolFee = await factory.getFee(poolAddress, stable);
  }
  poolFee = (poolFee * BigInt(10 ** 6)) / feeDivider; // scaled to decimals 6
  const GaugeFactory = await ethers.getContractFactory("MockGauge");
  const gauge = await GaugeFactory.deploy(poolAddress);
  await gauge.waitForDeployment();
  const gaugeAddress = await gauge.getAddress();
  const args = [
    admin.address,
    ionAddress,
    pairTokenAddress,
    stable,
    poolType,
    poolFee,
    minterAddress,
    priceManagerAddress,
    pairedTokenType,
    factoryAddress,
    routerAddress,
    gaugeAddress,
    admin.address, // rewardVault
    0, // tokenId
    false, // useTokenId
    validRangeWidth,
    sellRatio,
    buyRatio,
    sellIonRatioLimit,
    removeLiquidityRatioLimit,
    periodDuration
  ];
  const V2AMOFactory = await ethers.getContractFactory("V2AMO");
  const amo = await upgrades.deployProxy(V2AMOFactory, args, {
    initializer: "initialize"
  });
  await amo.waitForDeployment();
  const SETTER_ROLE = await amo.SETTER_ROLE();
  await amo.connect(admin).grantRole(SETTER_ROLE, admin);
  return amo;
}

export async function deployV3AMO(
  admin: SignerWithAddress,
  ionAddress: string,
  pairTokenAddress: string,
  poolAddress: string,
  poolType: V3PoolType,
  minterAddress: string,
  priceManagerAddress: string,
  pairedTokenType: number,
  tickLower: number,
  tickUpper: number,
  validRangeWidth: bigint,
  sellRatio: bigint,
  buyRatio: bigint,
  sellIonRatioLimit: bigint = ethers.parseUnits("10", 6),
  removeLiquidityRatioLimit: bigint = ethers.parseUnits("1", 6),
  periodDuration: bigint = 1n
): Promise<V3AMO> {
  if (pairedTokenType === PairTokenType.STABLE) {
    const priceManager = await ethers.getContractAt("PriceManager", priceManagerAddress);
    const timestamp = await time.latest();
    await priceManager.connect(admin).setStable(pairTokenAddress, ethers.parseUnits("1", 6), timestamp);
  }
  const args = [
    admin.address,
    ionAddress,
    pairTokenAddress,
    poolAddress,
    poolType,
    ethers.ZeroAddress, // poolCustomDeployer
    minterAddress,
    priceManagerAddress,
    pairedTokenType,
    tickLower,
    tickUpper,
    validRangeWidth,
    sellRatio,
    buyRatio,
    sellIonRatioLimit,
    removeLiquidityRatioLimit,
    periodDuration
  ];
  const V3AMOFactory = await ethers.getContractFactory("V3AMO");
  const amo = await upgrades.deployProxy(V3AMOFactory, args, {
    initializer: "initialize"
  });
  await amo.waitForDeployment();
  return amo;
}

async function _beforeCreatePool(ion: Ion, pairToken: MockERC20, price: bigint): Promise<[string, string, bigint]> {
  const ionAddress = await ion.getAddress();
  const ionDecimals = await ion.decimals();
  const pairTokenAddress = await pairToken.getAddress();
  const pairTokenDecimals = await pairToken.decimals();
  if (pairTokenAddress.toLowerCase() < ionAddress.toLowerCase()) price = BigInt(10 ** 12) / price;
  let priceX96 = Number((price * BigInt(2 ** 192)) / BigInt(10 ** 6));
  const decimalsDiff = Number(ionDecimals - pairTokenDecimals);
  if (ionAddress.toLowerCase() < pairTokenAddress.toLowerCase()) priceX96 /= 10 ** decimalsDiff;
  else priceX96 *= 10 ** decimalsDiff;
  let sqrtPriceX96 = BigInt(Math.floor(Math.sqrt(priceX96)));
  return [ionAddress, pairTokenAddress, sqrtPriceX96];
}

export async function createCLPool(
  factoryAddress: string,
  ion: Ion,
  pairToken: MockERC20,
  price: bigint,
  tickSpacing: number
): Promise<string> {
  const [ionAddress, pairTokenAddress, sqrtPriceX96] = await _beforeCreatePool(ion, pairToken, price);
  const poolFactory = await ethers.getContractAt("ICLFactory", factoryAddress);
  await poolFactory.createPool(ionAddress, pairTokenAddress, tickSpacing, sqrtPriceX96);
  return await poolFactory.getPool(ionAddress, pairTokenAddress, tickSpacing);
}

export async function createRamsesPool(
  factoryAddress: string,
  ion: Ion,
  pairToken: MockERC20,
  price: bigint,
  fee: number
): Promise<string> {
  const [ionAddress, pairTokenAddress, sqrtPriceX96] = await _beforeCreatePool(ion, pairToken, price);
  const poolFactory = await ethers.getContractAt("IRamsesV2Factory", factoryAddress);
  await poolFactory.createPool(ionAddress, pairTokenAddress, fee);
  const poolAddress = await poolFactory.getPool(ionAddress, pairTokenAddress, fee);
  const pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress);
  await pool.initialize(sqrtPriceX96);
  return poolAddress;
}

export async function createSolidlyPool(
  factoryAddress: string,
  ion: Ion,
  pairToken: MockERC20,
  price: bigint,
  fee: number,
  tickSpacing: number
): Promise<string> {
  const [ionAddress, pairTokenAddress, sqrtPriceX96] = await _beforeCreatePool(ion, pairToken, price);

  const poolFactory1 = await ethers.getContractAt("IRamsesV2Factory", factoryAddress);
  await poolFactory1.createPool(ionAddress, pairTokenAddress, fee);

  const poolFactory2 = await ethers.getContractAt("ICLFactory", factoryAddress);
  const poolAddress = await poolFactory2.getPool(ionAddress, pairTokenAddress, tickSpacing);

  const pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress);
  await pool.initialize(sqrtPriceX96);

  return poolAddress;
}

export async function createAlgebraPool(
  factoryAddress: string,
  ion: Ion,
  pairToken: MockERC20,
  price: bigint,
  poolCreator?: SignerWithAddress
): Promise<string> {
  const [ionAddress, pairTokenAddress, sqrtPriceX96] = await _beforeCreatePool(ion, pairToken, price);
  const poolFactory = await ethers.getContractAt("IAlgebraFactory", factoryAddress);
  if (poolCreator === undefined) {
    await poolFactory.createPool(ionAddress, pairTokenAddress);
  } else {
    await poolFactory.connect(poolCreator).createPool(ionAddress, pairTokenAddress);
  }
  const poolAddress = await poolFactory.poolByPair(ionAddress, pairTokenAddress);
  const pool = await ethers.getContractAt("IUniswapV3Pool", poolAddress);
  await pool.initialize(sqrtPriceX96);
  return poolAddress;
}

export async function addV2Liquidity(
  admin: SignerWithAddress,
  routerAddress: string,
  ion: Ion,
  pairToken: MockERC20,
  amo: V2AMO,
  amount: string,
  price: bigint = ethers.parseUnits("1", 6)
) {
  const router = await ethers.getContractAt("ISolidlyRouter", routerAddress);
  const ionAmount = ethers.parseUnits(amount, 18);
  let pairTokenAmount = ethers.parseUnits(amount, await pairToken.decimals());
  pairTokenAmount = (pairTokenAmount * price) / BigInt(10 ** 6);
  await ion.connect(admin).approve(routerAddress, ionAmount);
  await pairToken.connect(admin).approve(routerAddress, pairTokenAmount);
  await router.connect(admin).addLiquidity(
    await ion.getAddress(),
    await pairToken.getAddress(),
    false, // stable
    ionAmount,
    pairTokenAmount,
    0, // min amounts = 0 for testing
    0,
    await amo.getAddress(),
    ethers.MaxUint256
  );
  // Deposit all LP tokens to the gauge
  await amo.connect(admin).enableStaking(true);
}

export async function v3Swap(
  user: SignerWithAddress,
  poolCaller: MockUniswapV3PoolCaller,
  token0: MockERC20 | Ion,
  token1: MockERC20 | Ion,
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

export async function v2VeloSwap(
  user: SignerWithAddress,
  token0: MockERC20 | Ion,
  token1: MockERC20 | Ion,
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

export async function v2Swap(
  user: SignerWithAddress,
  token0: MockERC20 | Ion,
  token1: MockERC20 | Ion,
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
  const router = await ethers.getContractAt("ISolidlyRouter", routerAddress);
  const route = [
    {
      from: await token0.getAddress(),
      to: await token1.getAddress(),
      stable: false
    }
  ];
  await token0.connect(user).approve(routerAddress, amount);
  await token1.connect(user).approve(routerAddress, amount);
  await router.connect(user).swapExactTokensForTokens(amount, 0, route, user.address, deadline);
}

export async function getTargetPrice(amo: V2AMO | V3AMO, log: boolean = false): Promise<bigint> {
  const tp = await amo.ionTargetPriceInPairToken();
  if (log) console.log("Target Price: ", Number(tp) / 1e6);
  return tp;
}

export async function getCurrentPrice(amo: V2AMO | V3AMO, log: boolean = false): Promise<bigint> {
  const cp = await amo.ionPriceInPairToken();
  if (log) console.log("Current Price:", Number(cp) / 1e6);
  return cp;
}

export async function logPriceDiff(amo: V2AMO | V3AMO, indents: number = 2): Promise<{ tp: bigint; cp: bigint }> {
  const tp = await amo.ionTargetPriceInPairToken();
  const cp = await amo.ionPriceInPairToken();
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
