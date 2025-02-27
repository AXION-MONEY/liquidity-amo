import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { BoostStablecoin, Minter, MockERC20, PriceManager, V2AMO } from "../../typechain-types";
import {
  addV2Liquidity,
  deployBaseContracts,
  deployV2AMO,
  getCurrentPrice,
  getInitPrice,
  getTestCaseTitle,
  initNetwork,
  logPriceDiff,
  PairedTokenType,
  pairedTokenTypeName,
  V2PoolType,
  v2Swap
} from "./utils";

describe("EQUALIZER", function () {
  const rpcUrl = "https://rpc.soniclabs.com";
  const forkingBlock = 10025000;
  const swapAmounts = ["900000"];
  const LOG_PRICES = false;
  const initAmount = "11000000"; // 11M
  const lpAmount = "1000000"; // 1M
  const delta = ethers.parseUnits("0.00001", 6);
  const pairedTokenTypesToTest = [PairedTokenType.SUSDE, PairedTokenType.STABLE];
  const usdDecimalsToTest = [6, 18];

  // AMO consts
  const boostMultiplier = ethers.parseUnits("1.01", 6);
  const validRangeWidth = ethers.parseUnits("0.01", 6);
  const validRemovingRatio = ethers.parseUnits("1.01", 6);
  const boostLowerPriceSell = ethers.parseUnits("0.99", 6);
  const boostUpperPriceBuy = ethers.parseUnits("1.01", 6);

  // V2 consts
  const V2_ROUTER = "0xcC6169aA1E879d3a4227536671F85afdb2d23fAD"; // Router03
  const boostSellRatio = ethers.parseUnits("1", 6);
  const usdBuyRatio = ethers.parseUnits("1", 6);

  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let boost: BoostStablecoin;
  let usd: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
  let v2amo: V2AMO;

  for (const pairedTokenType of pairedTokenTypesToTest) {
    describe(`Paired token type: ${pairedTokenTypeName(pairedTokenType)}`, function () {
      for (const usdDecimals of usdDecimalsToTest) {
        describe(`USD decimals: ${usdDecimals}`, function () {
          describe("V2AMO", function () {
            before(async () => {
              [admin, user, priceManager] = await initNetwork(rpcUrl, forkingBlock);
              console.log(`\t\t\t\t\tNetwork init for V2AMO ${pairedTokenTypeName(pairedTokenType)}\t${usdDecimals}`);
            });
            beforeEach(async function () {
              [boost, usd, minter] = await deployBaseContracts(admin, user, usdDecimals, initAmount);

              const initPrice = await getInitPrice(priceManager, pairedTokenType);

              v2amo = await deployV2AMO(
                admin,
                await boost.getAddress(),
                await usd.getAddress(),
                V2PoolType.EQUAL_LIKE,
                await minter.getAddress(),
                await priceManager.getAddress(),
                pairedTokenType,
                V2_ROUTER,
                boostMultiplier,
                validRangeWidth,
                validRemovingRatio,
                boostLowerPriceSell,
                boostUpperPriceBuy,
                boostSellRatio,
                usdBuyRatio
              );
              const amoAddress = await v2amo.getAddress();
              const AMO_ROLE = await minter.AMO_ROLE();
              await minter.connect(admin).grantRole(AMO_ROLE, amoAddress);
              await addV2Liquidity(admin, V2_ROUTER, boost, usd, amoAddress, lpAmount, initPrice);
            });

            describe("V2 Public mintSellFarm", () => {
              for (const swapAmount of swapAmounts) {
                it(getTestCaseTitle(swapAmount), async function () {
                  await v2Swap(user, usd, boost, V2_ROUTER, swapAmount);
                  const { tp, cp } = await logPriceDiff(v2amo);
                  if (Number(swapAmount) > 0) {
                    await v2amo.mintSellFarm();
                    const newPrice = await getCurrentPrice(v2amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v2amo.mintSellFarm())
                      .to.be.revertedWithCustomError(v2amo, "InvalidReserveRatio")
                      .withArgs(cp);
                  }
                });
              }
            });

            describe("V2 Public unfarmBuyBurn", () => {
              for (const swapAmount of swapAmounts) {
                it(getTestCaseTitle(swapAmount, false), async function () {
                  await v2Swap(user, boost, usd, V2_ROUTER, swapAmount);
                  const { tp, cp } = await logPriceDiff(v2amo);
                  if (Number(swapAmount) > 0) {
                    await v2amo.unfarmBuyBurn();
                    const newPrice = await getCurrentPrice(v2amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v2amo.unfarmBuyBurn())
                      .to.be.revertedWithCustomError(v2amo, "InvalidReserveRatio")
                      .withArgs(cp);
                  }
                });
              }
            });
          });
        });
      }
    });
  }
});
