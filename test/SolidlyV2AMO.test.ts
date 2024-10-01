import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
// @ts-ignore
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  Minter,
  BoostStablecoin,
  MockERC20,
  SolidlyV2AMO,
  IV2Voter,
  IFactory,
  MockRouter
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
  let Router: MockRouter;


  let setterRole: any;
  let amoRole: any;
  let withdrawerRole: any;
  let pauserRole: any;
  let unpauserRole: any;

  const V2_VOTER = "0xE3D1A117dF7DCaC2eB0AC8219341bAd92f18dAC1";// Equalizer voter addresses
  const V2_FACTORY = "0xc6366EFD0AF1d09171fe0EBF32c7943BB310832a";
  const boostDesired = ethers.parseUnits("11000000", 18); // 10M
  const collateralDesired = ethers.parseUnits("11000000", 6); // 10M
  const boostMin4Liqudity = ethers.parseUnits("9990000", 18);
  const collateralMin4Liqudity = ethers.parseUnits("9990000", 6);

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


    //  deploy router
    const RouterFactory = await ethers.getContractFactory("MockRouter", admin);
    Router = await RouterFactory.deploy(
      V2_FACTORY,
      "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83"
    );
    await Router.waitForDeployment();

    // Deploy SolidlyV3AMO using upgrades.deployProxy
    const SolidlyV2LiquidityAMOFactory = await ethers.getContractFactory("SolidlyV2AMO");
    const args = [
      admin.address, // admin
      await boost.getAddress(),
      await testUSD.getAddress(),
      await minter.getAddress(),
      await Router.getAddress(),
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

    // provide liquidity
    await boost.approve(await Router.getAddress(), boostDesired);
    await testUSD.approve(await Router.getAddress(), collateralDesired);

    await Router.connect(admin).addLiquidity(
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
    setterRole = await solidlyV2AMO.SETTER_ROLE();
    amoRole = await solidlyV2AMO.AMO_ROLE();
    withdrawerRole = await solidlyV2AMO.WITHDRAWER_ROLE();
    pauserRole = await solidlyV2AMO.PAUSER_ROLE();
    unpauserRole = await solidlyV2AMO.UNPAUSER_ROLE();

    await solidlyV2AMO.grantRole(setterRole, setter.address);
    await solidlyV2AMO.grantRole(amoRole, amo.address);
    await solidlyV2AMO.grantRole(withdrawerRole, withdrawer.address);
    await solidlyV2AMO.grantRole(pauserRole, pauser.address);
    await solidlyV2AMO.grantRole(unpauserRole, unpauser.address);
    await minter.grantRole(await minter.AMO_ROLE(), await solidlyV2AMO.getAddress());
  });

  it("should initialize with correct parameters", async function() {
    expect(await solidlyV2AMO.boost()).to.equal(await boost.getAddress());
    expect(await solidlyV2AMO.usd()).to.equal(await testUSD.getAddress());
    expect(await solidlyV2AMO.boostMinter()).to.equal(await minter.getAddress());
  });


  it("should only allow SETTER_ROLE to call setParams", async function() {
    // Try calling setParams without SETTER_ROLE
    await expect(
      solidlyV2AMO.connect(user).setParams(
        ethers.toBigInt("1100000"),
        100000,
        990000,
        ethers.parseUnits("0.95", 6),
        ethers.parseUnits("1.05", 6),
        990000,
        10000
      )
    ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${setterRole}`);

    // Call setParams with SETTER_ROLE
    await expect(
      solidlyV2AMO.connect(setter).setParams(
        ethers.toBigInt("1100000"),
        100000,
        990000,
        ethers.parseUnits("0.95", 6),
        ethers.parseUnits("1.05", 6),
        990000,
        10000
      )
    ).to.emit(solidlyV2AMO, "ParamsSet");
  });

  it("should only allow AMO_ROLE to call mintAndSellBoost", async function() {
    const boostAddress = (await boost.getAddress()).toLowerCase();
    const testUSDAddress = (await testUSD.getAddress()).toLowerCase();
    const usdToBuy = ethers.parseUnits("1000000", 6);
    const minBoostReceive = ethers.parseUnits("990000", 18);
    const routeBuyBoost = [{
      from: await testUSD.getAddress(), // TestUSD address
      to: await boost.getAddress(), // BABE token address
      stable: true
    }];

    // Deadline for the transaction (current time + 60 seconds)
    const deadline = Math.floor(Date.now() / 1000) + 60;
    await testUSD.connect(admin).mint(user.address, usdToBuy);
    await testUSD.connect(user).approve(await Router.getAddress(), usdToBuy);
    await Router.connect(user).swapExactTokensForTokens(
      usdToBuy,
      minBoostReceive,
      routeBuyBoost,
      user.address,
      Math.floor(Date.now() / 1000) + 60 * 10
    );

    const boostAmount = ethers.parseUnits("990000", 18);
    const usdAmount = ethers.parseUnits("990000", 6);

    await expect(
      solidlyV2AMO.connect(user).mintAndSellBoost(
        boostAmount,
        usdAmount,
        Math.floor(Date.now() / 1000) + 60 * 10
      )
    ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${amoRole}`);

    await expect(
      solidlyV2AMO.connect(amo).mintAndSellBoost(
        boostAmount,
        usdAmount,
        Math.floor(Date.now() / 1000) + 60 * 10
      )
    ).to.emit(solidlyV2AMO, "MintSell");
    expect(await solidlyV2AMO.boostPrice()).to.be.approximately(ethers.parseUnits("1", 6), 10);
  });


  it("should only allow AMO_ROLE to call addLiquidity", async function() {
    const usdAmountToAdd = ethers.parseUnits("1000", 6);
    const boostMinAmount = ethers.parseUnits("900", 18);
    const usdMinAmount = ethers.parseUnits("900", 6);
    await testUSD.connect(admin).mint(await solidlyV2AMO.getAddress(), usdAmountToAdd);

    await expect(
      solidlyV2AMO.connect(user).addLiquidity(
        usdAmountToAdd,
        boostMinAmount,
        usdMinAmount,
        Math.floor(Date.now() / 1000) + 60 * 10
      )
    ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${amoRole}`);

    await expect(
      solidlyV2AMO.connect(amo).addLiquidity(
        usdAmountToAdd,
        boostMinAmount,
        usdMinAmount,
        Math.floor(Date.now() / 1000) + 60 * 10
      )
    ).to.emit(solidlyV2AMO, "AddLiquidityAndDeposit");
  });


  it("should only allow PAUSER_ROLE to pause and UNPAUSER_ROLE to unpause", async function() {
    await expect(solidlyV2AMO.connect(pauser).pause()).to.emit(solidlyV2AMO, "Paused").withArgs(pauser.address);

    await expect(
      solidlyV2AMO.connect(amo).mintAndSellBoost(
        ethers.parseUnits("1000", 18),
        ethers.parseUnits("950", 6),
        Math.floor(Date.now() / 1000) + 60 * 10
      )
    ).to.be.revertedWith("Pausable: paused");

    await expect(solidlyV2AMO.connect(unpauser).unpause()).to.emit(solidlyV2AMO, "Unpaused").withArgs(unpauser.address);
  });

  it("should allow WITHDRAWER_ROLE to withdraw ERC20 tokens", async function() {
    // Transfer some tokens to the contract
    await testUSD.connect(user).mint(await solidlyV2AMO.getAddress(), ethers.parseUnits("1000", 6));

    // Try withdrawing tokens without WITHDRAWER_ROLE
    await expect(
      solidlyV2AMO.connect(user).withdrawERC20(await testUSD.getAddress(), ethers.parseUnits("1000", 6), user.address)
    ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${withdrawerRole}`);

    // Withdraw tokens with WITHDRAWER_ROLE
    await solidlyV2AMO.connect(withdrawer).withdrawERC20(await testUSD.getAddress(), ethers.parseUnits("1000", 6), user.address);
    const usdBalanceOfUser = await testUSD.balanceOf(await user.getAddress());
    expect(usdBalanceOfUser).to.be.equal(ethers.parseUnits("1000", 6));
  });

  it("should execute public mintSellFarm when price above 1", async function() {
    const usdToBuy = ethers.parseUnits("1000000", 6);
    const minBoostReceive = ethers.parseUnits("990000", 18);
    const routeBuyBoost = [{
      from: await testUSD.getAddress(), // TestUSD address
      to: await boost.getAddress(), // BABE token address
      stable: true
    }];
    console.log(await solidlyV2AMO.boostPrice());
    // Deadline for the transaction (current time + 60 seconds)
    await testUSD.connect(admin).mint(user.address, usdToBuy);
    await testUSD.connect(user).approve(await Router.getAddress(), usdToBuy);
    await Router.connect(user).swapExactTokensForTokens(
      usdToBuy,
      minBoostReceive,
      routeBuyBoost,
      user.address,
      Math.floor(Date.now() / 1000) + 60 * 10
    );
    console.log(await solidlyV2AMO.boostPrice());

    expect(await solidlyV2AMO.boostPrice()).to.be.gt(ethers.parseUnits("1", 6));
    // await expect(solidlyV2AMO.connect(user).mintSellFarm()).to.be.emit(solidlyV3AMO, "PublicMintSellFarmExecuted");
    // expect(await solidlyV2AMO.boostPrice()).to.be.approximately(ethers.parseUnits("1", 6), 10);
  });

  it("should correctly return boostPrice", async function() {
    expect(await solidlyV2AMO.boostPrice()).to.be.approximately(ethers.parseUnits("1", 6), 10);
  });

  it("should revert when invalid parameters are set", async function() {
    await expect(
      solidlyV2AMO.connect(setter).setParams(
        ethers.toBigInt("1100000"),
        2000000,
        990000,
        ethers.parseUnits("0.95", 6),
        ethers.parseUnits("1.05", 6),
        990000,
        10000
      )
    ).to.be.revertedWithCustomError(solidlyV2AMO, "InvalidRatioValue");
  });


});
