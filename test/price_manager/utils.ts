import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { Minter, BoostStablecoin, MockERC20, PriceManager, V2AMO } from "../../typechain-types";

export async function deployBaseContracts(
  admin: SignerWithAddress,
  user: SignerWithAddress,
  initAmount: bigint
): Promise<[BoostStablecoin, MockERC20, Minter, PriceManager]> {
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

  return [boost, testUsd, minter, priceManager];
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

export async function addLiquidity(
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

export async function swap(
  user: SignerWithAddress,
  token0Address: string,
  token1Address: string,
  routerAddress: string,
  amount: bigint
) {
  const deadline = Math.floor(Date.now() / 1000) + 60 * 100;
  const router = await ethers.getContractAt("IVRouter", routerAddress);
  const route = [
    {
      from: token0Address,
      to: token1Address,
      stable: false,
      factory: ethers.ZeroAddress
    }
  ];
  await router.connect(user).swapExactTokensForTokens(amount, 0, route, user.address, deadline);
}
