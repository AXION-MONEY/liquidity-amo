import { expect } from "chai";
import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  BoostStablecoin,
  Minter,
  MockERC20,
  PriceManager,
  V2AMO,
} from "../../typechain-types";
import { deployBaseContracts, deployV2AMO, addLiquidity } from "./utils";

enum PairedTokenType {
  STABLE,
  SUSDE,
  SFRAX,
  SDAI,
}

const sigs = {
  susde: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress,
      },
      gatewaySignature: ethers.ZeroHash,
      token: "susde",
    },
    states: {
      totalSupply: "3734814116804093597606146132",
      balance: "4304104583370657539163990168",
      lastDistributionTimestamp: "1738207835",
      vestingAmount: "460055794761904761904761",
    },
  },
  sfrax: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress,
      },
      gatewaySignature: ethers.ZeroHash,
      token: "sfrax",
    },
    states: {
      totalSupply: "71228619772829715106592883",
      storedTotalAssets: "79039466004482887067661211",
      rewardsCycleData: {
        cycleEnd: "1738800000",
        lastSync: "1738195271",
        rewardCycleAmount: "578157898242524520561322",
      },
      lastRewardsDistribution: "1738219139",
      maxDistributionPerSecondPerAsset: "3329556719",
    },
  },
  sdai: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: ethers.ZeroHash,
      signature: {
        signature: 0,
        owner: ethers.ZeroAddress,
        nonce: ethers.ZeroAddress,
      },
      gatewaySignature: ethers.ZeroHash,
      token: "sdai",
    },
    states: {
      dsr: "1000000003380572527855758393",
      chi: "1141443554266986624494275064",
      rho: "1738222919",
    },
  },
};

describe("V2AMO", function () {
  const stable = false;
  const toBuy = stable ? "5000000" : "1000000";
  const fee = stable ? "0.0005" : "0.003";
  const poolFee = ethers.parseUnits(fee, 6);

  // Constants
  const AeroRouter = "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43";
  // Amounts and addresses
  const initAmount = ethers.parseUnits("11000000", 18); // 11M
  const lpAmount = ethers.parseUnits("1000000", 18); // 1M
  const delta = ethers.parseUnits("0.0001", 6);
  const boostMultiplier = ethers.parseUnits("1.1", 6);
  const validRangeWidth = ethers.parseUnits("0.01", 6);
  const validRemovingRatio = ethers.parseUnits("1.01", 6);
  const boostLowerPriceSell = ethers.parseUnits("0.99", 6);
  const boostUpperPriceBuy = ethers.parseUnits("1.01", 6);
  const boostSellRatio = ethers.parseUnits("1", 6);
  const usdBuyRatio = ethers.parseUnits("1", 6);
  let admin: SignerWithAddress;
  let user: SignerWithAddress;

  let boost: BoostStablecoin;
  let usd: MockERC20;
  let minter: Minter;
  let priceManager: PriceManager;
  let amo: V2AMO;

  before(async () => {
    [admin, user] = await ethers.getSigners();
    console.log("forking network...");
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://base-rpc.publicnode.com",
            blockNumber: 25717500, // Optional: specify a block number
          },
        },
      ],
    });
  });

  describe("Aerodrome V2Pool Tests", function () {
    beforeEach(async function () {
      [boost, usd, minter, priceManager] = await deployBaseContracts(
        admin,
        user,
        initAmount,
      );

      await priceManager
        .connect(user)
        .setSUsdeWithSig(sigs.susde.states, sigs.susde.muonSig);
      await priceManager
        .connect(user)
        .setSFraxWithSig(sigs.sfrax.states, sigs.sfrax.muonSig);
      await priceManager
        .connect(user)
        .setPotWithSig(sigs.sdai.states, sigs.sdai.muonSig);

      amo = await deployV2AMO(
        admin,
        await boost.getAddress(),
        await usd.getAddress(),
        poolFee,
        await minter.getAddress(),
        await priceManager.getAddress(),
        PairedTokenType.SUSDE,
        AeroRouter,
        boostMultiplier,
        validRangeWidth,
        validRemovingRatio,
        boostLowerPriceSell,
        boostUpperPriceBuy,
        boostSellRatio,
        usdBuyRatio,
      );
      const amoAddress = await amo.getAddress();
      const AMO_ROLE = await minter.AMO_ROLE();
      await minter.connect(admin).grantRole(AMO_ROLE, amoAddress);
      await addLiquidity(admin, AeroRouter, boost, usd, amoAddress, lpAmount);
    });
    describe("Staked Tokens", () => {
      it("Public mintSellFarm", async function () {
        const tp = await amo.targetPrice();
        console.log(tp);
        console.log(await amo.boostPrice());

        await amo["mintSellFarm()"]();

        const newPrice = await amo.boostPrice();
        console.log(newPrice);

        expect(newPrice).to.be.approximately(tp, delta);
      });
      it("Public unfarmBuyBurn", async function () {
        const tp = await amo.targetPrice();
        console.log(tp);
        console.log(await amo.boostPrice());

        await amo["unfarmBuyBurn()"]();

        const newPrice = await amo.boostPrice();
        console.log(newPrice);

        expect(newPrice).to.be.approximately(tp, delta);
      });
    });
  });
});
