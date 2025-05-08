import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MuonClient, PriceManager } from "../../typechain-types";

async function deployPriceManager(): Promise<[PriceManager, MuonClient]> {
  const validGateway = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const appId = "93307625660435442793252976666474786944683615644156490137714125190800568256860"; // "axion"
  const pubKey = { x: "0x4d116e81a9a511fb5fe12175050cdb4fab872afc2e291ba4ad9373468c9829be", parity: "0" };
  const checkGatewaySignature = true;
  const MuonClientFactory = await ethers.getContractFactory("MuonClient");
  const muonClient = await MuonClientFactory.deploy(validGateway, appId, pubKey, checkGatewaySignature);
  await muonClient.waitForDeployment();
  const muonClientAddress = await muonClient.getAddress();
  const stablePriceLower = ethers.parseUnits("0.9", 6);
  const stablePriceUpper = ethers.parseUnits("1.1", 6);

  const [admin, , tokenUpdater, setter] = await ethers.getSigners();
  const PriceManagerFactory = await ethers.getContractFactory("PriceManager");
  const priceManager = await upgrades.deployProxy(
    PriceManagerFactory,
    [admin.address, tokenUpdater.address, setter.address, muonClientAddress, stablePriceLower, stablePriceUpper],
    {
      initializer: "initialize"
    }
  );
  await priceManager.waitForDeployment();

  return [priceManager, muonClient];
}

const sigs = {
  susde: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: "0xcc1ef76e741dcb1e6dafa6c550378ff917887a63ab46a249579048609f91f12f",
      signature: {
        signature: "0xa17354e74b56a829a529f9495e69ff03cc947339650ae5b15ac5db0af9d94269",
        owner: "0xdD11751cdD3f6EFf01B1f6151B640685bfa5dB4a",
        nonce: "0xc3C449b4fb65C79a85Daf7158E4514501CC1ab47"
      },
      gatewaySignature:
        "0x98d6ba923137cbe77977fcc2e951bad31e86a044a096b1d92f855c1ef6a209067a1d743aee115056f65a728d8e7a2227db43eea9f9a05ae654a2eb427aaf12091b",
      token: "susde"
    },
    states: {
      totalSupply: "3734814116804093597606146132",
      balance: "4304104583370657539163990168",
      lastDistributionTimestamp: "1738207835",
      vestingAmount: "460055794761904761904761"
    },
    price: 1152428
  },
  sfrax: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: "0x26e661e74012ea8dcad8422623d0653e4a13ba289af988ca97815d72dc6c9d77",
      signature: {
        signature: "0xab1f3cc2576a44f62ec0fe93d858291c72698e0c4ce856badf37fca942702768",
        owner: "0xdD11751cdD3f6EFf01B1f6151B640685bfa5dB4a",
        nonce: "0xf291dF1d3f45dB980EF43Fee6079a76b7F682C4A"
      },
      gatewaySignature:
        "0x4e3f69ccd8888186a8cdbf478f7a823cd8a3c0c6986f1297a6907f238b1ae06454fcbc34c9c05741c9742a590b470076055b3366cbd4ea54834220bf820e69a81b",
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
    },
    price: 1111804
  },
  sdai: {
    muonSig: {
      srcBlock: { number: 21736000, timestamp: 1738223759 },
      reqId: "0x4e256824dfc6d4674969b4521dca35ebc86ec86fb382dd663a625361cb896e7d",
      signature: {
        signature: "0x1089c843e17f9a71c60719e330fbe551315f6906dc8ad694c58c8eacbd5d2b01",
        owner: "0xdD11751cdD3f6EFf01B1f6151B640685bfa5dB4a",
        nonce: "0x6EE04a54C77E524717ca016c073C19D008914a95"
      },
      gatewaySignature:
        "0x50ae8c96a9069f3915db0cdb8d2f7390c4e1dd0ec440434a38e4c196e2ab3aa07ba6a164b2b3d03358c7ad7d3f2e5bce04a71a10b9e35b2441b4057d621b9b521b",
      token: "sdai"
    },
    states: {
      dsr: "1000000003380572527855758393",
      chi: "1141443554266986624494275064",
      rho: "1738222919"
    },
    price: 1614713
  }
};
const stakedTokens = [
  {
    name: "susde",
    setFunction: "setSUsde",
    setWthSigFunction: "setSUsdeWithSig",
    previewRedeem: "sUsdePreviewRedeem",
    previewDeposit: "sUsdePreviewDeposit"
  },
  {
    name: "sfrax",
    setFunction: "setSFrax",
    setWthSigFunction: "setSFraxWithSig",
    previewRedeem: "sFraxPreviewRedeem",
    previewDeposit: "sFraxPreviewDeposit"
  },
  {
    name: "sdai",
    setFunction: "setPot",
    setWthSigFunction: "setPotWithSig",
    previewRedeem: "sDaiPreviewRedeem",
    previewDeposit: "sDaiPreviewDeposit"
  }
];

describe("PriceManager tests", function () {
  const baseUnit = ethers.parseUnits("1", 6);
  let user: SignerWithAddress;
  let tokenUpdater: SignerWithAddress;
  let priceManager: PriceManager;
  before(async function () {
    await ethers.provider.send("evm_setNextBlockTimestamp", [1840827900]);
    await ethers.provider.send("evm_mine");
  });
  beforeEach(async function () {
    [priceManager] = await deployPriceManager();
    [, user, tokenUpdater] = await ethers.getSigners();
  });
  for (const token of stakedTokens) {
    describe(token.name.toUpperCase(), function () {
      // @ts-ignore
      const sig = sigs[token.name];
      const inversePrice = Math.floor(10 ** 12 / sig.price);
      it(token.setFunction, async function () {
        // @ts-ignore
        await priceManager.connect(tokenUpdater)[token.setFunction](sig.states, sig.muonSig.srcBlock);
        // @ts-ignore
        expect(await priceManager[token.previewRedeem](baseUnit)).to.be.equal(sig.price);
        // @ts-ignore
        expect(await priceManager[token.previewDeposit](baseUnit)).to.be.approximately(inversePrice, 1);
      });
      it(token.setWthSigFunction, async function () {
        // @ts-ignore
        await priceManager.connect(user)[token.setWthSigFunction](sig.states, sig.muonSig);
        // @ts-ignore
        expect(await priceManager[token.previewRedeem](baseUnit)).to.be.equal(sig.price);
        // @ts-ignore
        expect(await priceManager[token.previewDeposit](baseUnit)).to.be.approximately(inversePrice, 1);
      });
    });
  }
});

describe("Complete coverage", function () {
  const baseUnit = ethers.parseUnits("1", 6);
  let admin: SignerWithAddress;
  let tokenUpdater: SignerWithAddress;
  let priceManager: PriceManager;
  let muonClient: MuonClient;
  let srcBlock: any;
  let states: any;
  before(async function () {
    await network.provider.request({ method: "hardhat_reset", params: [] });
  });
  describe("SUSDE", function () {
    beforeEach(async function () {
      [priceManager, muonClient] = await deployPriceManager();
      [admin, , tokenUpdater] = await ethers.getSigners();
      const currentBlock = await ethers.provider.getBlock("latest");
      srcBlock = { number: 21736000, timestamp: currentBlock!.timestamp };
      states = {
        totalSupply: "3734814116804093597606146132",
        balance: "4304104583370657539163990168",
        lastDistributionTimestamp: currentBlock!.timestamp - 100,
        vestingAmount: "460055794761904761904761"
      };
    });
    it("Should revert with invalid block", async function () {
      srcBlock.timestamp += 10;
      await expect(priceManager.connect(tokenUpdater).setSUsde(states, srcBlock)).to.be.revertedWithCustomError(
        priceManager,
        "InvalidBlock"
      );
    });
    it("Should set states", async function () {
      await priceManager.connect(tokenUpdater).setSUsde(states, srcBlock);
      expect(await priceManager.sUsdePreviewRedeem(baseUnit)).to.be.gt(baseUnit);
    });
  });
  describe("MuonClient", function () {
    it("Should set variables", async function () {
      await muonClient.setAppId(0);
      await muonClient.setValidGateway(ethers.ZeroAddress);
      await muonClient.setPubKey({ x: ethers.ZeroHash, parity: 0 });
      await muonClient.setCheckGatewaySignature(false);
    });
  });
});
