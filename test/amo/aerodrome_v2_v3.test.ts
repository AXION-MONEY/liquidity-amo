import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { Ion, Minter, MockERC20, MockUniswapV3PoolCaller, PriceManager, V2AMO, V3AMO } from "../../typechain-types";
import {
  addV2Liquidity,
  createCLPool,
  deployBaseContracts,
  deployV2AMO,
  deployV3AMO,
  getCurrentPrice,
  getInitPrice,
  getTestCaseTitle,
  getTickBounds,
  initNetwork,
  logPriceDiff,
  PairTokenType,
  pairedTokenTypeName,
  V2PoolType,
  v2VeloSwap,
  V3PoolType,
  v3Swap
} from "./utils";

describe("AERODROME", function () {
  const rpcUrl = "https://developer-access-mainnet.base.org";
  const forkingBlock = 26235850;
  const priceBounds = [
    [undefined, undefined], // full range
    ["0.7", "1.5"],
    ["0.5", "2.0"],
    ["0.1", "10.0"]
  ];
  const swapAmounts = ["900000", "0", "-5000"];
  let tickSpacing = 1; // Valid values for Aero: [1, 50, 100, 200, 2_000]
  const LOG_PRICES = false;
  const initAmount = "11000000"; // 11M
  const lpAmount = "1000000"; // 1M
  const delta = ethers.parseUnits("0.00001", 6);
  const pairTokenTypesToTest = [PairTokenType.SUSDE, PairTokenType.STABLE];
  const pairTokenDecimalsToTest = [6, 18];

  // AMO consts
  const _vrw = tickSpacing == 2_000 ? "0.02" : "0.01";
  const validRangeWidth = ethers.parseUnits(_vrw, 6);
  const sellRatio = ethers.parseUnits("1", 6);
  const buyRatio = ethers.parseUnits("1", 6);

  // V2 consts
  const AERO_V2_ROUTER = "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43";

  // V3 consts
  const AERO_POOL_FACTORY = "0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A";

  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let ion: Ion;
  let pairToken: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
  let v2amo: V2AMO;
  let v3amo: V3AMO;
  let poolCaller: MockUniswapV3PoolCaller;

  for (const pairedTokenType of pairTokenTypesToTest) {
    describe(`Paired token type: ${pairedTokenTypeName(pairedTokenType)}`, function () {
      for (const pairTokenDecimals of pairTokenDecimalsToTest) {
        describe(`Pair token decimals: ${pairTokenDecimals}`, function () {
          describe("V3AMO", function () {
            before(async () => {
              [admin, user, priceManager] = await initNetwork(rpcUrl, forkingBlock);
              console.log(
                `\t\t\t\t\tNetwork init for V3AMO ${pairedTokenTypeName(pairedTokenType)}\t${pairTokenDecimals}`
              );
            });
            beforeEach(async function () {
              [ion, pairToken, minter] = await deployBaseContracts(admin, user, pairTokenDecimals, initAmount);
              const initPrice = await getInitPrice(priceManager, pairedTokenType);
              const poolAddress = await createCLPool(AERO_POOL_FACTORY, ion, pairToken, initPrice, tickSpacing);
              const factory = await ethers.getContractFactory("MockUniswapV3PoolCaller");
              poolCaller = await factory.deploy(poolAddress);
              await poolCaller.waitForDeployment();

              const [lowerPriceValue, upperPriceValue] = priceBounds[3];
              const { tickLower, tickUpper } = await getTickBounds(
                ion,
                pairToken,
                tickSpacing,
                lowerPriceValue,
                upperPriceValue
              );
              v3amo = await deployV3AMO(
                admin,
                await ion.getAddress(),
                await pairToken.getAddress(),
                poolAddress,
                V3PoolType.CL,
                await minter.getAddress(),
                await priceManager.getAddress(),
                pairedTokenType,
                tickLower,
                tickUpper,
                validRangeWidth,
                sellRatio,
                buyRatio
              );
              const amoAddress = await v3amo.getAddress();
              const AMO_ROLE = await minter.AMO_ROLE();
              await minter.connect(admin).grantRole(AMO_ROLE, amoAddress);
              const pairTokenAmount = (ethers.parseUnits(lpAmount, pairTokenDecimals) * initPrice) / BigInt(10 ** 6);
              await pairToken.connect(admin).mint(amoAddress, pairTokenAmount);
              await v3amo.addLiquidity();
            });

            describe("V3 Public mintSellFarm", () => {
              for (const swapAmount of swapAmounts) {
                it(getTestCaseTitle(swapAmount), async function () {
                  await v3Swap(user, poolCaller, pairToken, ion, swapAmount);
                  const { tp, cp } = await logPriceDiff(v3amo);
                  if (Number(swapAmount) > 0) {
                    await v3amo.mintSellFarm();
                    const newPrice = await getCurrentPrice(v3amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v3amo.mintSellFarm())
                      .to.be.revertedWithCustomError(v3amo, "PriceAlreadyInRange")
                      .withArgs(cp);
                  }
                });
              }
            });

            describe("V3 Public unfarmBuyBurn", () => {
              for (const swapAmount of swapAmounts) {
                it(getTestCaseTitle(swapAmount, true), async function () {
                  await v3Swap(user, poolCaller, ion, pairToken, swapAmount);
                  const { tp, cp } = await logPriceDiff(v3amo);
                  if (Number(swapAmount) > 0) {
                    await v3amo.unfarmBuyBurn();
                    const newPrice = await getCurrentPrice(v3amo, LOG_PRICES);
                    expect(newPrice).to.be.approximately(tp, delta);
                  } else {
                    await expect(v3amo.unfarmBuyBurn())
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
              console.log(
                `\t\t\t\t\tNetwork init for V2AMO ${pairedTokenTypeName(pairedTokenType)}\t${pairTokenDecimals}`
              );
            });
            beforeEach(async function () {
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
            });

            describe("V2 Public mintSellFarm", () => {
              for (const swapAmount of swapAmounts) {
                it(getTestCaseTitle(swapAmount), async function () {
                  await v2VeloSwap(user, pairToken, ion, AERO_V2_ROUTER, swapAmount);
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
                  await v2VeloSwap(user, ion, pairToken, AERO_V2_ROUTER, swapAmount);
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
