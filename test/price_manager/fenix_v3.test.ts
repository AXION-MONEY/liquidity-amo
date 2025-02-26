import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  BoostStablecoin,
  Minter,
  MockERC20,
  MockUniswapV3PoolCaller,
  PriceManager,
  V3AMO
} from "../../typechain-types";
import {
  deployBaseContracts,
  deployV3AMO,
  getCurrentPrice,
  getInitPrice,
  getTestCaseTitle,
  getTickBounds,
  initNetwork,
  logPriceDiff,
  PairedTokenType,
  pairedTokenTypeName,
  V3PoolType,
  v3Swap,
  createAlgebraPool
} from "./utils";

describe("FENIX", function () {
  const rpcUrl = "https://blast.gateway.tenderly.co";
  const forkingBlock = 15841400;
  const priceBounds = [
    [undefined, undefined], // full range
    ["0.7", "1.5"],
    ["0.5", "2.0"],
    ["0.1", "10.0"]
  ];
  const swapAmounts = ["900000"];
  let tickSpacing = 60;
  const LOG_PRICES = false;
  const initAmount = "11000000"; // 11M
  const lpAmount = "1000000"; // 1M
  const delta = ethers.parseUnits("0.00001", 6);
  const pairedTokenTypesToTest = [PairedTokenType.SUSDE, PairedTokenType.STABLE];
  const usdDecimalsToTest = [6, 18];

  // AMO consts
  const boostMultiplier = ethers.parseUnits("1.01", 6);
  const _vrw = tickSpacing == 200 ? "0.02" : "0.01";
  const validRangeWidth = ethers.parseUnits(_vrw, 6);
  const validRemovingRatio = ethers.parseUnits("1.01", 6);
  const boostLowerPriceSell = ethers.parseUnits("0.99", 6);
  const boostUpperPriceBuy = ethers.parseUnits("1.01", 6);

  // V3 consts
  const POOL_FACTORY = "0x7a44CD060afC1B6F4c80A2B9b37f4473E74E25Df"; // AlgebraFactory
  const QUOTER = "0x94Ca5B835186A37A99776780BF976fAB81D84ED8"; // QuoterV2
  const POOLS_CREATOR = "0x0d24BE6fa556a2fa18054A7787ed2c76dEbFf458";
  const ALGEBRA_FACTORY_OWNER = "0x0907fb24626a06e383BD289A0e9C8560b8cCC4b5";

  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  let poolCreator: SignerWithAddress;

  let boost: BoostStablecoin;
  let usd: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
  let v3amo: V3AMO;
  let poolCaller: MockUniswapV3PoolCaller;

  for (const pairedTokenType of pairedTokenTypesToTest) {
    describe(`Paired token type: ${pairedTokenTypeName(pairedTokenType)}`, function () {
      for (const usdDecimals of usdDecimalsToTest) {
        describe(`USD decimals: ${usdDecimals}`, function () {
          describe("V3AMO", function () {
            before(async () => {
              [admin, user, priceManager] = await initNetwork(rpcUrl, forkingBlock);
              poolCreator = await ethers.getImpersonatedSigner(POOLS_CREATOR);
              await ethers.provider.send("hardhat_setBalance", [POOLS_CREATOR, "0xde0b6b3a7640000"]);
              const factoryOwner = await ethers.getImpersonatedSigner(ALGEBRA_FACTORY_OWNER);
              await ethers.provider.send("hardhat_setBalance", [ALGEBRA_FACTORY_OWNER, "0xde0b6b3a7640000"]);
              const algebraFactory = await ethers.getContractAt("IAlgebraIntegralPool", POOL_FACTORY);
              await algebraFactory.connect(factoryOwner).setDefaultCommunityFee(0);
              await algebraFactory.connect(factoryOwner).setVaultFactory(ethers.ZeroAddress);
              console.log(`\t\t\t\t\tNetwork init for V3AMO ${pairedTokenTypeName(pairedTokenType)}\t${usdDecimals}`);
            });
            beforeEach(async function () {
              [boost, usd, minter] = await deployBaseContracts(admin, user, usdDecimals, initAmount);
              const initPrice = await getInitPrice(priceManager, pairedTokenType);
              const poolAddress = await createAlgebraPool(POOL_FACTORY, boost, usd, initPrice, poolCreator);
              const factory = await ethers.getContractFactory("MockUniswapV3PoolCaller");
              poolCaller = await factory.deploy(poolAddress);
              await poolCaller.waitForDeployment();

              const [lowerPriceValue, upperPriceValue] = priceBounds[0];
              const { tickLower, tickUpper } = await getTickBounds(
                boost,
                usd,
                tickSpacing,
                lowerPriceValue,
                upperPriceValue
              );
              v3amo = await deployV3AMO(
                admin,
                await boost.getAddress(),
                await usd.getAddress(),
                poolAddress,
                V3PoolType.ALGEBRA_INTEGRAL,
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
        });
      }
    });
  }
});
