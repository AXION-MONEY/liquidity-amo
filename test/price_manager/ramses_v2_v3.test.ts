import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  BoostStablecoin,
  Minter,
  MockERC20,
  MockUniswapV3PoolCaller,
  PriceManager,
  V2AMO,
  V3AMO
} from "../../typechain-types";
import {
  addV2Liquidity,
  createRamsesPool,
  deployBaseContracts,
  deployV2AMO,
  deployV3AMO,
  getCurrentPrice,
  getInitPrice,
  getTestCaseTitle,
  getTickBounds,
  initNetwork,
  logPriceDiff,
  PairedTokenType,
  pairedTokenTypeName,
  V2PoolType,
  V3PoolType,
  v2Swap,
  v3Swap
} from "./utils";

describe("Price Manager tests", function () {
  const rpcUrl = "https://arbitrum.rpc.subquery.network/public";
  const forkingBlock = 308991000;
  const priceBounds = [
    [undefined, undefined], // full range
    ["0.7", "1.5"],
    ["0.5", "2.0"],
    ["0.1", "10.0"]
  ];
  const swapAmounts = ["900000"];
  let v3Fee = 100; // Valid (fee, tickSpacing) values for Ramses: [(100, 1), (500, 10), (3000, 60), (10000, 200)]
  const LOG_PRICES = true;
  const initAmount = "11000000"; // 11M
  const lpAmount = "1000000"; // 1M
  const delta = ethers.parseUnits("0.00001", 6);
  const pairedTokenTypesToTest = [PairedTokenType.SUSDE, PairedTokenType.STABLE];
  const usdDecimalsToTest = [6, 18];

  // AMO consts
  const boostMultiplier = ethers.parseUnits("1.01", 6);
  const _vrw = v3Fee == 10_000 ? "0.02" : "0.01";
  const validRangeWidth = ethers.parseUnits(_vrw, 6);
  const validRemovingRatio = ethers.parseUnits("1.01", 6);
  const boostLowerPriceSell = ethers.parseUnits("0.99", 6);
  const boostUpperPriceBuy = ethers.parseUnits("1.01", 6);

  // V2 consts
  const V2_ROUTER = "0xAAA87963EFeB6f7E0a2711F397663105Acb1805e"; // Router
  const poolFee = ethers.parseUnits("0.003", 6);
  const boostSellRatio = ethers.parseUnits("1", 6);
  const usdBuyRatio = ethers.parseUnits("1", 6);

  // V3 consts
  const POOL_FACTORY = "0xAA2cd7477c451E703f3B9Ba5663334914763edF8"; // RamsesV2Factory
  const QUOTER = "0xAA20EFF7ad2F523590dE6c04918DaAE0904E3b20"; // QuoterV2

  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let boost: BoostStablecoin;
  let usd: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
  let v2amo: V2AMO;
  let v3amo: V3AMO;
  let poolCaller: MockUniswapV3PoolCaller;

  for (const pairedTokenType of pairedTokenTypesToTest) {
    describe(`Paired token type: ${pairedTokenTypeName(pairedTokenType)}`, function () {
      for (const usdDecimals of usdDecimalsToTest) {
        describe(`USD decimals: ${usdDecimals}`, function () {
          describe("V3AMO", function () {
            before(async () => {
              [admin, user, priceManager] = await initNetwork(rpcUrl, forkingBlock);
              console.log(`\t\t\t\t\tNetwork init for V3AMO ${pairedTokenTypeName(pairedTokenType)}\t${usdDecimals}`);
            });
            beforeEach(async function () {
              [boost, usd, minter] = await deployBaseContracts(admin, user, usdDecimals, initAmount);
              const initPrice = await getInitPrice(priceManager, pairedTokenType);
              const pool = await createRamsesPool(POOL_FACTORY, boost, usd, initPrice, v3Fee);
              const factory = await ethers.getContractFactory("MockUniswapV3PoolCaller");
              poolCaller = await factory.deploy(await pool.getAddress());
              await poolCaller.waitForDeployment();

              const [lowerPriceValue, upperPriceValue] = priceBounds[0];
              const { tickLower, tickUpper } = await getTickBounds(boost, usd, v3Fee, lowerPriceValue, upperPriceValue);
              v3amo = await deployV3AMO(
                admin,
                await boost.getAddress(),
                await usd.getAddress(),
                await pool.getAddress(),
                V3PoolType.RAMSES_V2,
                QUOTER,
                await minter.getAddress(),
                await priceManager.getAddress(),
                pairedTokenType,
                tickLower,
                tickUpper,
                boostMultiplier,
                validRangeWidth,
                validRemovingRatio,
                boostLowerPriceSell,
                boostUpperPriceBuy
              );
              const amoAddress = await v3amo.getAddress();
              const AMO_ROLE = await minter.AMO_ROLE();
              await minter.connect(admin).grantRole(AMO_ROLE, amoAddress);
              const usdAmount = (ethers.parseUnits(lpAmount, usdDecimals) * initPrice) / BigInt(10 ** 6);
              await usd.connect(admin).mint(amoAddress, usdAmount);
              await v3amo.connect(admin).addLiquidity(usdAmount, 0, 0);
            });

            describe("V3 Public mintSellFarm", () => {
              for (const swapAmount of swapAmounts) {
                it(getTestCaseTitle(swapAmount), async function () {
                  await v3Swap(user, poolCaller, usd, boost, swapAmount);
                  const { tp, cp } = await logPriceDiff(v3amo);
                  if (Number(swapAmount) > 0) {
                    await v3amo["mintSellFarm()"]();
                    const newPrice = await getCurrentPrice(v3amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v3amo["mintSellFarm()"]())
                      .to.be.revertedWithCustomError(v3amo, "PriceAlreadyInRange")
                      .withArgs(cp);
                  }
                });
              }
            });

            describe("V3 Public unfarmBuyBurn", () => {
              for (const swapAmount of swapAmounts) {
                it(getTestCaseTitle(swapAmount, true), async function () {
                  await v3Swap(user, poolCaller, boost, usd, swapAmount);
                  const { tp, cp } = await logPriceDiff(v3amo);
                  if (Number(swapAmount) > 0) {
                    await v3amo["unfarmBuyBurn()"]();
                    const newPrice = await getCurrentPrice(v3amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v3amo["unfarmBuyBurn()"]())
                      .to.be.revertedWithCustomError(v3amo, "PriceAlreadyInRange")
                      .withArgs(cp);
                  }
                });
              }
            });
          });

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
                poolFee,
                V2PoolType.SOLIDLY_V2,
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
                    await v2amo["mintSellFarm()"]();
                    const newPrice = await getCurrentPrice(v2amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v2amo["mintSellFarm()"]())
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
                    await v2amo["unfarmBuyBurn()"]();
                    const newPrice = await getCurrentPrice(v2amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v2amo["unfarmBuyBurn()"]())
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
