import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { Ion, Minter, MockERC20, PriceManager, V2AMO } from "../../typechain-types";
import {
  addV2Liquidity,
  deployBaseContracts,
  deployV2AMO,
  getCurrentPrice,
  getInitPrice,
  initNetwork,
  PairTokenType,
  V2PoolType,
  v2VeloSwap
} from "./utils";

describe("Missed Statements", () => {
  const rpcUrl = "https://base.llamarpc.com";
  const forkingBlock = 29474850;
  const swapAmount = "200000";
  const LOG_PRICES = false;
  const initAmount = "11000000"; // 11M
  const lpAmount = "1000000"; // 1M
  const delta = ethers.parseUnits("0.00001", 6);
  const pairedTokenType = PairTokenType.SUSDE;
  const pairTokenDecimals = 18;

  // AMO consts
  const validRangeWidth = ethers.parseUnits("0.01", 6);
  const sellRatio = ethers.parseUnits("0.8", 6);
  const buyRatio = ethers.parseUnits("0.8", 6);

  // V2 consts
  const AERO_V2_ROUTER = "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43";

  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let ion: Ion;
  let pairToken: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
  let v2amo: V2AMO;
  let OPERATOR_ROLE: string;

  beforeEach(async () => {
    [admin, user, priceManager] = await initNetwork(rpcUrl, forkingBlock);
    [ion, pairToken, minter] = await deployBaseContracts(admin, user, pairTokenDecimals, initAmount);

    v2amo = await deployV2AMO(
      admin,
      await ion.getAddress(),
      await pairToken.getAddress(),
      V2PoolType.VELO_LIKE,
      await minter.getAddress(),
      await priceManager.getAddress(),
      pairedTokenType,
      AERO_V2_ROUTER,
      validRangeWidth,
      sellRatio,
      buyRatio
    );
    const amoAddress = await v2amo.getAddress();
    const AMO_ROLE = await minter.AMO_ROLE();
    await minter.connect(admin).grantRole(AMO_ROLE, amoAddress);
    const initPrice = await getInitPrice(priceManager, pairedTokenType);
    await addV2Liquidity(admin, AERO_V2_ROUTER, ion, pairToken, amoAddress, lpAmount, initPrice);

    const SETTER_ROLE = await v2amo.SETTER_ROLE();
    const PAUSER_ROLE = await v2amo.PAUSER_ROLE();
    const UNPAUSER_ROLE = await v2amo.UNPAUSER_ROLE();
    const WITHDRAWER_ROLE = await v2amo.WITHDRAWER_ROLE();
    const REWARD_COLLECTOR_ROLE = await v2amo.REWARD_COLLECTOR_ROLE();
    await v2amo.connect(admin).grantRole(SETTER_ROLE, admin);
    await v2amo.connect(admin).grantRole(PAUSER_ROLE, admin);
    await v2amo.connect(admin).grantRole(UNPAUSER_ROLE, admin);
    await v2amo.connect(admin).grantRole(WITHDRAWER_ROLE, admin);
    await v2amo.connect(admin).grantRole(REWARD_COLLECTOR_ROLE, admin);

    OPERATOR_ROLE = await v2amo.OPERATOR_ROLE();
  });

  it("set ION target price premium", async () => {
    const premiumValue = ethers.parseUnits("0.02", 6);
    expect(await v2amo.ionTargetPricePremium()).to.be.equal(0);
    await v2amo.connect(admin).setIonTargetPricePremium(premiumValue);
    expect(await v2amo.ionTargetPricePremium()).to.be.equal(premiumValue);
  });

  it("pause & unpause", async () => {
    expect(await v2amo.paused()).to.be.equal(false);
    await v2amo.connect(admin).pause();
    expect(await v2amo.paused()).to.be.equal(true);
    await v2amo.connect(admin).unpause();
    expect(await v2amo.paused()).to.be.equal(false);
  });

  it("withdraw ERC20", async () => {
    const MockErc20Factory = await ethers.getContractFactory("MockERC20");
    const token = await MockErc20Factory.deploy("Token", "TOKEN", 18);
    await token.waitForDeployment();

    const amount = ethers.parseUnits("123.456", 6);
    await token.mint(v2amo, amount);
    expect(await token.balanceOf(v2amo)).to.be.equal(amount);
    expect(await token.balanceOf(user)).to.be.equal(0);
    await v2amo.connect(admin).withdrawERC20(token, amount, user);
    expect(await token.balanceOf(v2amo)).to.be.equal(0);
    expect(await token.balanceOf(user)).to.be.equal(amount);
  });

  it("remove liquidity", async () => {
    const liquidity = ethers.parseUnits("100000", 18);
    const balanceBefore = await pairToken.balanceOf(user);
    await v2amo.connect(admin).removeLiquidity(liquidity, 0, 0, user);
    expect(await pairToken.balanceOf(user)).to.be.gt(balanceBefore);
  });

  it("whitelist a token as reward", async () => {
    expect(await v2amo.whitelistedRewardTokens(pairToken)).to.be.equal(false);
    await v2amo.setWhitelistedTokens([pairToken], true);
    expect(await v2amo.whitelistedRewardTokens(pairToken)).to.be.equal(true);
  });

  it("get reward", async () => {
    await expect(v2amo.connect(admin).getReward([pairToken], false))
      .to.be.revertedWithCustomError(v2amo, "TokenNotWhitelisted")
      .withArgs(await pairToken.getAddress());
    await v2amo.setWhitelistedTokens([pairToken], true);
    await expect(v2amo.connect(admin).getReward([pairToken], false)).not.to.be.reverted;
  });

  it("mintSellFarm with & without swap ratio", async () => {
    const tp = await v2amo.ionTargetPriceInPairToken();

    await v2VeloSwap(user, pairToken, ion, AERO_V2_ROUTER, swapAmount);
    await v2amo.connect(admin).grantRole(OPERATOR_ROLE, user);
    await v2amo.connect(user).mintSellFarm();
    const newPrice1 = await getCurrentPrice(v2amo, LOG_PRICES);
    expect(newPrice1).to.be.approximately(tp, delta);

    await v2VeloSwap(user, pairToken, ion, AERO_V2_ROUTER, swapAmount);
    await v2amo.connect(admin).revokeRole(OPERATOR_ROLE, user);
    await v2amo.connect(user).mintSellFarm();
    const newPrice2 = await getCurrentPrice(v2amo, LOG_PRICES);
    expect(newPrice2).to.be.gt(tp + (tp * validRangeWidth) / 1000000n);
  });

  it("unfarmBuyBurn with & without swap ratio", async () => {
    const tp = await v2amo.ionTargetPriceInPairToken();

    await v2VeloSwap(user, ion, pairToken, AERO_V2_ROUTER, swapAmount);
    await v2amo.connect(admin).grantRole(OPERATOR_ROLE, user);
    await v2amo.connect(user).unfarmBuyBurn();
    const newPrice1 = await getCurrentPrice(v2amo, LOG_PRICES);
    expect(newPrice1).to.be.approximately(tp, delta);

    await v2VeloSwap(user, ion, pairToken, AERO_V2_ROUTER, swapAmount);
    await v2amo.connect(admin).revokeRole(OPERATOR_ROLE, user);
    await v2amo.connect(user).unfarmBuyBurn();
    const newPrice2 = await getCurrentPrice(v2amo, LOG_PRICES);
    expect(newPrice2).to.be.lt(tp - (tp * validRangeWidth) / 1000000n);
  });
});
