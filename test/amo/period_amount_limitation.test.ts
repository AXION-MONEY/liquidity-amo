import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { Ion, Minter, MockERC20, MockUniswapV3PoolCaller, PriceManager, V2AMO, V3AMO } from "../../typechain-types";
import {
  addV2Liquidity,
  createCLPool,
  deployBaseContracts,
  deployV2AMO,
  deployV3AMO,
  getInitPrice,
  getTickBounds,
  initNetwork,
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
  let tickSpacing = 1; // Valid values for Aero: [1, 50, 100, 200, 2_000]
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
  const sellIonRatioLimit = ethers.parseUnits("0.5", 6); // 50%
  const removeLiquidityRatioLimit = ethers.parseUnits("0.1", 6); // 10%
  const periodDuration = 600n;

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
            let tp: bigint;
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
                buyRatio,
                sellIonRatioLimit,
                removeLiquidityRatioLimit,
                periodDuration
              );
              const amoAddress = await v3amo.getAddress();
              const OPERATOR_ROLE = await v3amo.OPERATOR_ROLE();
              await v3amo.connect(admin).grantRole(OPERATOR_ROLE, admin);

              const AMO_ROLE = await minter.AMO_ROLE();
              await minter.connect(admin).grantRole(AMO_ROLE, amoAddress);
              const pairTokenAmount = (ethers.parseUnits(lpAmount, pairTokenDecimals) * initPrice) / BigInt(10 ** 6);
              await pairToken.connect(admin).mint(amoAddress, pairTokenAmount);
              await v3amo.addLiquidity();
              tp = await v3amo.ionTargetPriceInPairToken();
            });

            describe("V3 mintSellFarm: No allowed amount in current period", () => {
              beforeEach(async () => {
                await v3Swap(user, poolCaller, pairToken, ion, "600000");
                await v3amo.connect(user).mintSellFarm();
                expect(await v3amo.ionPriceInPairToken()).not.to.be.approximately(tp, delta);
              });
              it("user should unable to execute operation (must wait for next period)", async function () {
                await expect(v3amo.connect(user).mintSellFarm()).to.be.revertedWithCustomError(
                  v3amo,
                  "NoAllowedAmount"
                );
                await time.increase(periodDuration);
                await v3amo.connect(user).mintSellFarm();
                expect(await v3amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
              it("operator role should bypass limitation", async function () {
                await v3amo.connect(admin).mintSellFarm();
                expect(await v3amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
            });

            describe("V3 unfarmBuyBurn: No allowed amount in current period", () => {
              beforeEach(async () => {
                await v3Swap(user, poolCaller, ion, pairToken, "200000");
                await v3amo.connect(user).unfarmBuyBurn();
                expect(await v3amo.ionPriceInPairToken()).not.to.be.approximately(tp, delta);
              });
              it("user should unable to execute operation (must wait for next period)", async function () {
                await expect(v3amo.connect(user).unfarmBuyBurn()).to.be.revertedWithCustomError(
                  v3amo,
                  "NoAllowedAmount"
                );
                await time.increase(periodDuration);
                await v3amo.connect(user).unfarmBuyBurn();
                expect(await v3amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
              it("operator role should bypass limitation", async function () {
                await v3amo.connect(admin).unfarmBuyBurn();
                expect(await v3amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
            });
          });

          describe("V2AMO", function () {
            let tp: bigint;
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
                buyRatio,
                sellIonRatioLimit,
                removeLiquidityRatioLimit,
                periodDuration
              );
              const amoAddress = await v2amo.getAddress();
              const OPERATOR_ROLE = await v2amo.OPERATOR_ROLE();
              await v2amo.connect(admin).grantRole(OPERATOR_ROLE, admin);

              const AMO_ROLE = await minter.AMO_ROLE();
              await minter.connect(admin).grantRole(AMO_ROLE, amoAddress);
              const initPrice = await getInitPrice(priceManager, pairedTokenType);
              await addV2Liquidity(admin, AERO_V2_ROUTER, ion, pairToken, v2amo, lpAmount, initPrice);
              tp = await v2amo.ionTargetPriceInPairToken();
            });

            describe("V2 mintSellFarm: No allowed amount in current period", () => {
              beforeEach(async () => {
                await v2VeloSwap(user, pairToken, ion, AERO_V2_ROUTER, "600000");
                await v2amo.connect(user).mintSellFarm();
                expect(await v2amo.ionPriceInPairToken()).not.to.be.approximately(tp, delta);
              });
              it("user should unable to execute operation (must wait for next period)", async function () {
                await expect(v2amo.connect(user).mintSellFarm()).to.be.revertedWithCustomError(
                  v2amo,
                  "NoAllowedAmount"
                );
                await time.increase(periodDuration);
                await v2amo.connect(user).mintSellFarm();
                expect(await v2amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
              it("operator role should bypass limitation", async function () {
                await v2amo.connect(admin).mintSellFarm();
                expect(await v2amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
            });

            describe("V2 unfarmBuyBurn: No allowed amount in current period", () => {
              beforeEach(async () => {
                await v2VeloSwap(user, ion, pairToken, AERO_V2_ROUTER, "200000");
                await v2amo.connect(user).unfarmBuyBurn();
                expect(await v2amo.ionPriceInPairToken()).not.to.be.approximately(tp, delta);
              });
              it("user should unable to execute operation (must wait for next period)", async function () {
                await expect(v2amo.connect(user).unfarmBuyBurn()).to.be.revertedWithCustomError(
                  v2amo,
                  "NoAllowedAmount"
                );
                await time.increase(periodDuration);
                await v2amo.connect(user).unfarmBuyBurn();
                expect(await v2amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
              it("operator role should bypass limitation", async function () {
                await v2amo.connect(admin).unfarmBuyBurn();
                expect(await v2amo.ionPriceInPairToken()).to.be.approximately(tp, delta);
              });
            });
          });
        });
      }
    });
  }
});
