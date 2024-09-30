import { expect } from "chai";
import hre, { ethers, network, upgrades } from "hardhat";
// @ts-ignore
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  Minter,
  BoostStablecoin,
  MockERC20,
  ISolidlyRouter,
  SolidlyV2AMO,
  IV2Voter,
  IFactory
} from "../typechain-types";

before(async () => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: "https://rpc.ftm.tools",
          blockNumber: 92000000 // Optional: specify a block number
        }
      }
    ]
  });
});

describe("SolidlyV2LiqAMO", function() {
  let solidlyV2AMO: SolidlyV2AMO;
  let boost: BoostStablecoin;
  let testUSD: MockERC20;
  let minter: Minter;
  let v2Router: ISolidlyRouter;
  let v2Voter: IV2Voter;
  let factory: IFactory;
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
  const V2_FACTORY = "0xc6366EFD0AF1d09171fe0EBF32c7943BB310832a";
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
    factory = await ethers.getContractAt("IFactory", V2_FACTORY);
    await factory.connect(admin).createPair(
      await boost.getAddress(),
      await testUSD.getAddress(),
      true
    );

    // Get poolAddress
    const poolAddress = await factory.getPair(
      await boost.getAddress(),
      await testUSD.getAddress(),
      true
    );

    // create Gauge
    v2Voter = await ethers.getContractAt("IV2Voter", V2_VOTER);
    const governor = await v2Voter.governor();
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [governor]
    });
    const governorSigner = await ethers.getSigner(governor);
    await v2Voter.connect(governorSigner).createGauge(poolAddress);
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [governor]
    });
    const gauge = await v2Voter.gauges(poolAddress);

    // Deploy SolidlyV3AMO using upgrades.deployProxy
    const SolidlyV2LiquidityAMOFactory = await ethers.getContractFactory("SolidlyV2AMO");
    const args = [
      admin.address, // admin
      await boost.getAddress(),
      await testUSD.getAddress(),
      await minter.getAddress(),
      V2_ROUTER,
      gauge,
      treasuryVault.address, //rewardVault_
      0, //tokenId_
      false, //useTokenId_
      ethers.toBigInt("1100000"), // boostMultiplier
      100000, // validRangeRatio
      990000, // validRemovingRatio
      ethers.parseUnits("0.95", 6), // boostLowerPriceSell
      ethers.parseUnits("1.05", 6), // boostUpperPriceBuy
      ethers.parseUnits("0.5", 18), //boostSellRatio
      990000 // usdUsageRatio
    ];
    solidlyV2AMO = (await upgrades.deployProxy(SolidlyV2LiquidityAMOFactory, args, {
      initializer: "initialize(address,address,address,address,address,address,address,uint256,bool,uint256,uint24,uint24,uint256,uint256,uint256,uint256)"
    })) as unknown as SolidlyV2AMO;
    await solidlyV2AMO.waitForDeployment();
    //
    // // Provide liquidity
    v2Router = await ethers.getContractAt("ISolidlyRouter", V2_ROUTER);
    await boost.approve(V2_ROUTER, boostDesired);
    await testUSD.approve(V2_ROUTER, collateralDesired);

    await v2Router.connect(admin).addLiquidity(
      await testUSD.getAddress(),
      await boost.getAddress(),
      true,
      collateralDesired,
      boostDesired,
      collateralMin4Liqudity,
      boostMin4Liqudity,
      admin.address,
      Math.floor(Date.now() / 1000) + 60 * 10
    );



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
