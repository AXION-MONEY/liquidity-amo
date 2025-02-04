import { expect } from "chai";
import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { BoostStablecoin, Minter, MockERC20, PriceManager, V2AMO, V3AMO } from "../../typechain-types";
import {
  PairedTokenType,
  deployBaseContracts,
  deployV2AMO,
  addV2Liquidity,
  getCurrentPrice,
  v2Swap,
  deployPriceManager,
  deployV3AMO,
  createCLPool,
  v3Swap,
  logPriceDiff,
  getTestCaseTitle,
  getInitPrice
} from "./utils";

const sigs = {
  susde: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress
      },
      gatewaySignature: ethers.ZeroHash,
      token: "susde"
    },
    states: {
      totalSupply: "3734814116804093597606146132",
      balance: "4304104583370657539163990168",
      lastDistributionTimestamp: "1738207835",
      vestingAmount: "460055794761904761904761"
    }
  },
  sfrax: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress
      },
      gatewaySignature: ethers.ZeroHash,
      token: "sfrax"
    },
    states: {
      totalSupply: "71228619772829715106592883",
      storedTotalAssets: "79039466004482887067661211",
      rewardsCycleData: {
        cycleEnd: "1738800000",
        lastSync: "1738195271",
        rewardCycleAmount: "578157898242524520561322"
      },
      lastRewardsDistribution: "1738219139",
      maxDistributionPerSecondPerAsset: "3329556719"
    }
  },
  sdai: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress
      },
      gatewaySignature: ethers.ZeroHash,
      token: "sdai"
    },
    states: {
      dsr: "1000000003380572527855758393",
      chi: "1141443554266986624494275064",
      rho: "1738222919"
    }
  }
};

describe("Price Manager tests", function () {
  const pairedTokenType = PairedTokenType.STABLE;
  const LOG_PRICES = false;
  const initAmount = ethers.parseUnits("11000000", 18); // 11M
  const lpAmount = ethers.parseUnits("1000000", 18); // 1M
  const delta = ethers.parseUnits("0.00001", 6);

  // AMO consts
  const boostMultiplier = ethers.parseUnits("1.1", 6);
  const validRangeWidth = ethers.parseUnits("0.01", 6);
  const validRemovingRatio = ethers.parseUnits("1.01", 6);
  const boostLowerPriceSell = ethers.parseUnits("0.99", 6);
  const boostUpperPriceBuy = ethers.parseUnits("1.01", 6);

  // V2 consts
  const AERO_V2_ROUTER = "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43";
  const poolFee = ethers.parseUnits("0.003", 6);
  const boostSellRatio = ethers.parseUnits("1", 6);
  const usdBuyRatio = ethers.parseUnits("1", 6);

  // V3 consts
  const AERO_POOL_FACTORY = "0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A";
  const AERO_QUOTER = "0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0";
  const AERO_V3_ROUTER = "0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5"; // SwapRouter
  const tickLower = -887272;
  const tickUpper = 887272;

  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let boost: BoostStablecoin;
  let usd: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
  let v2amo: V2AMO;
  let v3amo: V3AMO;

  before(async () => {
    [admin, user] = await ethers.getSigners();
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://base-rpc.publicnode.com",
            blockNumber: 25717500 // Optional: specify a block number
          }
        }
      ]
    });
    priceManager = await deployPriceManager(admin);
    await priceManager.connect(user).setSUsdeWithSig(sigs.susde.states, sigs.susde.muonSig);
    await priceManager.connect(user).setSFraxWithSig(sigs.sfrax.states, sigs.sfrax.muonSig);
    await priceManager.connect(user).setPotWithSig(sigs.sdai.states, sigs.sdai.muonSig);
  });

  describe("V3AMO", function () {
    beforeEach(async function () {
      [boost, usd, minter] = await deployBaseContracts(admin, user, initAmount);
      const initPrice = await getInitPrice(priceManager, pairedTokenType);
      const pool = await createCLPool(AERO_POOL_FACTORY, boost, usd, initPrice);

      v3amo = await deployV3AMO(
        admin,
        await boost.getAddress(),
        await usd.getAddress(),
        await pool.getAddress(),
        AERO_QUOTER,
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

      await boost.connect(admin).mint(amoAddress, lpAmount);
      await usd.connect(admin).mint(amoAddress, lpAmount);
      await v3amo.connect(admin).addLiquidity(lpAmount, 0, 0);
    });

    describe("V3 Public mintSellFarm", () => {
      for (const swapAmount of ["8000", "65000", "900000", "0", "-5000"]) {
        it(getTestCaseTitle(swapAmount), async function () {
          await v3Swap(user, usd, boost, AERO_V3_ROUTER, ethers.parseUnits(swapAmount, 18));
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
      for (const swapAmount of ["8000", "65000", "900000", "0", "-5000"]) {
        it(getTestCaseTitle(swapAmount, true), async function () {
          await v3Swap(user, boost, usd, AERO_V3_ROUTER, ethers.parseUnits(swapAmount, 18));
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
    beforeEach(async function () {
      [boost, usd, minter] = await deployBaseContracts(admin, user, initAmount);

      v2amo = await deployV2AMO(
        admin,
        await boost.getAddress(),
        await usd.getAddress(),
        poolFee,
        await minter.getAddress(),
        await priceManager.getAddress(),
        pairedTokenType,
        AERO_V2_ROUTER,
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
      const initPrice = await getInitPrice(priceManager, pairedTokenType);
      await addV2Liquidity(admin, AERO_V2_ROUTER, boost, usd, amoAddress, lpAmount, initPrice);
    });

    describe("V2 Public mintSellFarm", () => {
      for (const swapAmount of ["8000", "65000", "900000", "0", "-5000"]) {
        it(getTestCaseTitle(swapAmount), async function () {
          await v2Swap(user, usd, boost, AERO_V2_ROUTER, ethers.parseUnits(swapAmount, 18));
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
      for (const swapAmount of ["8000", "65000", "900000", "0", "-5000"]) {
        it(getTestCaseTitle(swapAmount, false), async function () {
          await v2Swap(user, boost, usd, AERO_V2_ROUTER, ethers.parseUnits(swapAmount, 18));
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
