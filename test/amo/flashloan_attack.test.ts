import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
    Ion,
    Minter,
    MockERC20,
    MockUniswapV3PoolCaller,
    PriceManager,
    V3AMO
} from "../../typechain-types";
import {
    createCLPool,
    deployBaseContracts,
    deployV3AMO,
    logPriceDiff,
    getCurrentPrice,
    getInitPrice,
    getTickBounds,
    initNetwork,
    PairTokenType,
    V3PoolType,
    v3Swap
} from "./utils";

const rpcUrl = "https://developer-access-mainnet.base.org";
const forkingBlock = 26235850;
const CL_FACTORY = "0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A";

const tickSpacing = 1;
const initAmount = "0";
const lpAmount = "1000000"; // 1M
const flashLoanUSD = "6000000"; // 6M
const flashLoanION = "6000000"; // 6M

const validRangeWidth = ethers.parseUnits("0.01", 6);
const sellIonRatioLimit = ethers.parseUnits("0.05", 6);
const removeLiquidityRatioLimit = ethers.parseUnits("0.05", 6);
const periodDuration = 3600n;

const delta = ethers.parseUnits("0.001", 6);

let admin: SignerWithAddress;
let attacker: SignerWithAddress;
let priceMgr: PriceManager;
let ion: Ion;
let usd: MockERC20;
let minter: Minter;
let amo: V3AMO;
let pool: MockUniswapV3PoolCaller;
let realPool: string;

before(async () => {
    [admin, attacker, priceMgr] = await initNetwork(rpcUrl, forkingBlock);
});

beforeEach(async () => {
    [ion, usd, minter] = await deployBaseContracts(admin, attacker, 6, initAmount);

    const initPx = await getInitPrice(priceMgr, PairTokenType.SUSDE);
    const poolAddr = await createCLPool(CL_FACTORY, ion, usd, initPx, tickSpacing);
    realPool = poolAddr;

    const F = await ethers.getContractFactory("MockUniswapV3PoolCaller");
    pool = await F.deploy(poolAddr);
    await pool.waitForDeployment();

    const { tickLower, tickUpper } = await getTickBounds(ion, usd, tickSpacing, undefined, undefined);

    amo = await deployV3AMO(
        admin,
        await ion.getAddress(),
        await usd.getAddress(),
        poolAddr,
        V3PoolType.CL,
        await minter.getAddress(),
        await priceMgr.getAddress(),
        PairTokenType.SUSDE,
        tickLower,
        tickUpper,
        validRangeWidth,
        ethers.parseUnits("1", 6),
        ethers.parseUnits("1", 6),
        sellIonRatioLimit,
        removeLiquidityRatioLimit,
        periodDuration
    );

    const AMO_ROLE = await minter.AMO_ROLE();
    await minter.connect(admin).grantRole(AMO_ROLE, await amo.getAddress());

    const usdSeed = (ethers.parseUnits(lpAmount, 6) * initPx) / BigInt(1e6);
    await usd.connect(admin).mint(await amo.getAddress(), usdSeed);
    await amo.addLiquidity();
});

describe("Flashloan attack scenarios", function () {
    describe("USD Flashloan", function () {
        it("attacker cannot profit or permanently distort price via a USD flashloan", async () => {
            // Flashloan the USD
            const flashAmt = ethers.parseUnits(flashLoanUSD, 6);
            await usd.connect(admin).mint(attacker.address, flashAmt);

            // Pump price: swap borrowed USD for ION
            await v3Swap(attacker, pool, usd, ion, flashLoanUSD);
            const priceAfterSwap = await amo.ionPriceInPairToken();
            const targetPx = await amo.ionTargetPriceInPairToken();
            expect(priceAfterSwap).to.be.gt(targetPx);

            // Optionally trigger mintSellFarm. it does not matter because attacker will lose too much usd
            // await amo.connect(attacker).mintSellFarm();

            // Attacker exits: swap all ION back to USD
            const ionBal = await ion.balanceOf(attacker.address);
            if (ionBal > 0n) {
                const ionToSell = ionBal / (10n ** 18n);
                await v3Swap(attacker, pool, ion, usd, ionToSell.toString());
            }

            // Attacker ends up with less USD than they borrowed
            const attackerUsdEnd = await usd.balanceOf(attacker.address);
            expect(attackerUsdEnd).to.be.lt(flashAmt);

            // Repay flashloan will revert due to insufficient balance
            await expect(
                usd.connect(attacker).transfer(minter.target, flashAmt)
            ).to.be.revertedWithCustomError(usd, "ERC20InsufficientBalance");
        });

        it("attacker willing to lose USD still cannot permanently distort price via flashloan", async () => {
            // Flashloan the USD
            const flashAmt = ethers.parseUnits(flashLoanUSD, 6);
            await usd.connect(admin).mint(attacker.address, flashAmt);

            // Give attacker USD to repay flashloan
            const initUsdAmount = flashAmt / 10n;
            await usd.connect(admin).mint(attacker.address, initUsdAmount);

            // Pump price: swap borrowed USD for ION
            await v3Swap(attacker, pool, usd, ion, flashLoanUSD);
            const targetPx = await amo.ionTargetPriceInPairToken();
            const afterPump = await amo.ionPriceInPairToken();
            expect(afterPump).to.be.gt(targetPx);

            // Attacker exits: swap all ION back to USD
            const ionBal = await ion.balanceOf(attacker.address);
            if (ionBal > 0n) {
                const toSell = ionBal / (10n ** 18n);
                await v3Swap(attacker, pool, ion, usd, toSell.toString());
            }

            // Repay flashloan
            await usd.connect(attacker).transfer(minter.target, flashAmt);

            // Attacker has lost USD
            const usdEnd = await usd.balanceOf(attacker.address);
            expect(usdEnd).to.be.lt(initUsdAmount);

            // Price should back near the target
            const afterExit = await amo.ionPriceInPairToken();
            await logPriceDiff(amo, 3); // Price is 0.02% above
            expect(afterExit).to.be.approximately(targetPx, delta);
        });
    });

    describe("ION Flashloan", function () {
        it("attacker cannot profit or permanently distort price via an ION flash‑loan", async () => {
            // Flashloan the ION
            const flashAmtION = ethers.parseUnits(flashLoanION, 18);
            await ion.connect(admin).mint(attacker.address, flashAmtION);

            // Dump price: swap ION for USD
            await v3Swap(attacker, pool, ion, usd, flashLoanION);
            const targetPx = await amo.ionTargetPriceInPairToken();
            const priceAfterDump = await amo.ionPriceInPairToken();
            expect(priceAfterDump).to.be.lt(targetPx);

            // Optionally trigger unfarmBuyBurn. it does not matter because attacker will lose too much ion
            // await amo.connect(attacker).unfarmBuyBurn();

            // Attacker exits: swap all USD back to ION
            const usdBal = await usd.balanceOf(attacker.address);
            if (usdBal > 0n) {
                const usdToSpend = usdBal / 10n ** 6n;
                await v3Swap(attacker, pool, usd, ion, usdToSpend.toString());
            }

            // Attacker ends up with less ION than they borrowed
            const ionEnd = await ion.balanceOf(attacker.address);
            expect(ionEnd).to.be.lt(flashAmtION);

            // Repay flashloan will revert due to insufficient balance
            await expect(
                ion.connect(attacker).transfer(admin.address, flashAmtION)
            ).to.be.revertedWithCustomError(ion, "ERC20InsufficientBalance");
        });

        it("attacker willing to lose ION still cannot permanently distort price", async () => {
            // Flashloan the ION
            const flashAmtION = ethers.parseUnits(flashLoanION, 18);
            await ion.connect(admin).mint(attacker.address, flashAmtION);

            // Give attacker IOn to repay flashloan
            const initIonAmount = flashAmtION / 10n;
            await ion.connect(admin).mint(attacker.address, initIonAmount);

            // Dump price: swap ION for USD
            await v3Swap(attacker, pool, ion, usd, flashLoanION);
            const targetPx = await amo.ionTargetPriceInPairToken();
            const afterDump = await amo.ionPriceInPairToken();
            expect(afterDump).to.be.lt(targetPx);

            // Attacker exits: swap all USD back to ION
            const usdBal = await usd.balanceOf(attacker.address);
            if (usdBal > 0n) {
                const usdToSpend = usdBal / 10n ** 6n;
                await v3Swap(attacker, pool, usd, ion, usdToSpend.toString());
            }

            // Repay flashloan
            await ion.connect(attacker).transfer(admin.address, flashAmtION);

            // Attacker ends up with less ION than they borrowed
            const ionEnd = await ion.balanceOf(attacker.address);
            expect(ionEnd).to.be.lt(initIonAmount);

            // Price should back near the target
            const finalPx = await amo.ionPriceInPairToken();                  // price back near target
            await logPriceDiff(amo, 3); // Price is 0.02% below
            expect(finalPx).to.be.approximately(targetPx, delta);
        });
    });

});
