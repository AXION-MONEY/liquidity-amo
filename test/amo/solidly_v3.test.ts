import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { Ion, Minter, MockERC20, MockUniswapV3PoolCaller, PriceManager, V3AMO } from "../../typechain-types";
import {
  deployBaseContracts,
  deployV3AMO,
  getCurrentPrice,
  getInitPrice,
  getTestCaseTitle,
  getTickBounds,
  initNetwork,
  logPriceDiff,
  PairTokenType,
  pairedTokenTypeName,
  V3PoolType,
  v3Swap,
  createSolidlyPool
} from "./utils";

describe("SOLIDLY", function () {
  const rpcUrl = "https://rpc.soniclabs.com";
  const forkingBlock = 10025000;
  const priceBounds = [
    [undefined, undefined], // full range
    ["0.7", "1.5"],
    ["0.5", "2.0"],
    ["0.1", "10.0"]
  ];
  const swapAmounts = ["900000"];
  let v3Fee = 100; // Valid (fee, tickSpacing) values for Solidly: [(100, 1), (500, 10), (3000, 50), (10000, 100)]
  let tickSpacing = 1;
  const LOG_PRICES = false;
  const initAmount = "11000000"; // 11M
  const lpAmount = "1000000"; // 1M
  const delta = ethers.parseUnits("0.00001", 6);
  const pairTokenTypesToTest = [PairTokenType.STABLE, PairTokenType.SDAI, PairTokenType.SFRAX, PairTokenType.SUSDE];
  const pairTokenDecimalsToTest = [18];

  // AMO consts
  const _vrw = tickSpacing == 200 ? "0.02" : "0.01";
  const validRangeWidth = ethers.parseUnits(_vrw, 6);
  const sellRatio = ethers.parseUnits("1", 6);
  const buyRatio = ethers.parseUnits("1", 6);

  // V3 consts
  const POOL_FACTORY = "0x777fAca731b17E8847eBF175c94DbE9d81A8f630"; // SolidlyV3Factory

  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let ion: Ion;
  let pairToken: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
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
              const poolAddress = await createSolidlyPool(POOL_FACTORY, ion, pairToken, initPrice, v3Fee, tickSpacing);
              const factory = await ethers.getContractFactory("MockUniswapV3PoolCaller");
              poolCaller = await factory.deploy(poolAddress);
              await poolCaller.waitForDeployment();

              const [lowerPriceValue, upperPriceValue] = priceBounds[0];
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
                V3PoolType.SOLIDLY_V3,
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
              const usdAmount = (ethers.parseUnits(lpAmount, pairTokenDecimals) * initPrice) / BigInt(10 ** 6);
              await pairToken.connect(admin).mint(amoAddress, usdAmount);
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
                      .withArgs(cp, tp);
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
                      .withArgs(cp, tp);
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
