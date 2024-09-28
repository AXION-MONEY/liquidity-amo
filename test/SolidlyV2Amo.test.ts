import { expect } from "chai";
import hre, { ethers, upgrades } from "hardhat";
// @ts-ignore
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  Minter,
  BoostStablecoin,
  MockERC20,
  ISolidlyV3Pool,
  ISolidlyRouter,
  SolidlyV2AMO,
  IV2Voter
} from "../typechain-types";
import { bigint } from "hardhat/internal/core/params/argumentTypes";

describe("SolidlyV2LiqAMO", function() {
  let solidlyV2AMO: SolidlyV2AMO;
  let boost: BoostStablecoin;
  let testUSD: MockERC20;
  let minter: Minter;
  let pool: ISolidlyV3Pool;
  let v2Router: ISolidlyRouter;
  let v2Voter: IV2Voter;
  let admin: SignerWithAddress;
  let treasuryVault: SignerWithAddress;
  let setter: SignerWithAddress;
  let amo: SignerWithAddress;
  let withdrawer: SignerWithAddress;
  let pauser: SignerWithAddress;
  let unpauser: SignerWithAddress;
  let boostMinter: SignerWithAddress;
  let user: SignerWithAddress;

  let setterRole: any;
  let amoRole: any;
  let withdrawerRole: any;
  let pauserRole: any;
  let unpauserRole: any;

  const V2_ROUTER = "0x1A05EB736873485655F29a37DEf8a0AA87F5a447"; // Equalizer router addresses
  const V2_VOTER = "0x4bebEB8188aEF8287f9a7d1E4f01d76cBE060d5b";// Equalizer voter addresses
  const MIN_SQRT_RATIO = BigInt("4295128739"); // Minimum sqrt price ratio
  const MAX_SQRT_RATIO = BigInt("1461446703485210103287273052203988822378723970342"); // Maximum sqrt price ratio
  let sqrtPriceX96: bigint;
  const liquidity = ethers.parseUnits("10000000", 12); // ~10M
  const boostDesired = ethers.parseUnits("11000000", 18); // 10M
  const collateralDesired = ethers.parseUnits("11000000", 6); // 10M
  const boostMin4Liqudity = ethers.parseUnits("9990000", 18);
  const collateralMin4Liqudity = ethers.parseUnits("9990000", 6);
  const tickLower = -887200;
  const tickUpper = 887200;
  const poolFee = 100;
  const price = "1";

  beforeEach(async function() {
    [admin, treasuryVault, setter, amo, withdrawer, pauser, unpauser, boostMinter, user] = await ethers.getSigners();
    console.log([admin, treasuryVault, setter, amo, withdrawer, pauser, unpauser, boostMinter, user] )

    // Deploy the actual contracts using deployProxy
    const BoostFactory = await ethers.getContractFactory("BoostStablecoin");
    boost = (await upgrades.deployProxy(BoostFactory, [admin.address])) as unknown as BoostStablecoin;
    await boost.waitForDeployment();

    const MockErc20Factory = await ethers.getContractFactory("MockERC20");
    testUSD = await MockErc20Factory.deploy("USD", "USD", 6);
    await testUSD.waitForDeployment();

    const MinterFactory = await ethers.getContractFactory("Minter");
    minter = (await upgrades.deployProxy(MinterFactory, [await boost.getAddress(), await testUSD.getAddress(), await admin.getAddress()])) as unknown as Minter;
    await minter.waitForDeployment();

    // Mint Boost and TestUSD
    await boost.grantRole(await boost.MINTER_ROLE(), await minter.getAddress());
    await boost.grantRole(await boost.MINTER_ROLE(), boostMinter.address);
    await boost.connect(boostMinter).mint(admin.address, boostDesired);
    await testUSD.connect(boostMinter).mint(admin.address, collateralDesired);

    // Create Pool
    v2Router = await ethers.getContractAt("ISolidlyRouter", V2_ROUTER);
    const [, , poolAddress] = await v2Router.connect(admin).addLiquidity(
      await boost.getAddress(),
      await testUSD.getAddress(),
      false,
      ethers.parseUnits("100", 18),
      ethers.parseUnits("100", 6),
      ethers.parseUnits("90", 18),
      ethers.parseUnits("90", 6),
      admin.address,
      Math.floor(Date.now() / 1000) + 60 * 10
    );

    // create Gauge
    v2Voter = await ethers.getContractAt("IV2Voter", V2_VOTER);
    const gauge = await v2Voter.connect(admin).createGauge(poolAddress);


    // Deploy SolidlyV3AMO using upgrades.deployProxy
    const SolidlyV2LiquidityAMOFactory = await ethers.getContractFactory("SolidlyV2AMO");
    const args = [
      admin.address, // admin
      await boost.getAddress(),
      await testUSD.getAddress(),
      await minter.getAddress(),
      await v2Router.getAddress(),
      gauge,
      treasuryVault.address, //rewardVault_
      "0x0000000000000000000000000000000000000000", //tokenId_
      false, //useTokenId_
      ethers.toBigInt("1100000"), // boostMultiplier
      100000, // validRangeRatio
      990000, // validRemovingRatio
      ethers.parseUnits("0.95", 6), // boostLowerPriceSell
      ethers.parseUnits("1.05", 6), // boostUpperPriceBuy
      990000, // usdUsageRatio
    ];
    solidlyV2AMO = (await upgrades.deployProxy(SolidlyV2LiquidityAMOFactory, args)) as unknown as SolidlyV2AMO;
    await solidlyV2AMO.waitForDeployment();
    //
    // // Provide liquidity
    // await boost.approve(pool_address, boostDesired);
    // await testUSD.approve(pool_address, collateralDesired);
    //
    // let amount0Min, amount1Min;
    // if ((await boost.getAddress()).toLowerCase() < (await testUSD.getAddress()).toLowerCase()) {
    //   amount0Min = boostMin4Liqudity;
    //   amount1Min = collateralMin4Liqudity;
    // } else {
    //   amount1Min = boostMin4Liqudity;
    //   amount0Min = collateralMin4Liqudity;
    // }
    // await pool.mint(
    //   await solidlyV3AMO.getAddress(),
    //   tickLower,
    //   tickUpper,
    //   liquidity,
    //   amount0Min,
    //   amount1Min,
    //   Math.floor(Date.now() / 1000) + 60 * 10
    // );
    //
    // // Grant Roles
    // setterRole = await solidlyV3AMO.SETTER_ROLE();
    // amoRole = await solidlyV3AMO.AMO_ROLE();
    // withdrawerRole = await solidlyV3AMO.WITHDRAWER_ROLE();
    // pauserRole = await solidlyV3AMO.PAUSER_ROLE();
    // unpauserRole = await solidlyV3AMO.UNPAUSER_ROLE();
    //
    // await solidlyV3AMO.grantRole(setterRole, setter.address);
    // await solidlyV3AMO.grantRole(amoRole, amo.address);
    // await solidlyV3AMO.grantRole(withdrawerRole, withdrawer.address);
    // await solidlyV3AMO.grantRole(pauserRole, pauser.address);
    // await solidlyV3AMO.grantRole(unpauserRole, unpauser.address);
    // await minter.grantRole(await minter.AMO_ROLE(), await solidlyV3AMO.getAddress());
  });

  it("should initialize with correct parameters", async function() {
    // expect(await solidlyV3AMO.boost()).to.equal(await boost.getAddress());
    // expect(await solidlyV3AMO.usd()).to.equal(await testUSD.getAddress());
    // expect(await solidlyV3AMO.pool()).to.equal(await pool.getAddress());
    // expect(await solidlyV3AMO.boostMinter()).to.equal(await minter.getAddress());
  });


});
