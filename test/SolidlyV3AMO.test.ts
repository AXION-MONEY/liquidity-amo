import {expect} from "chai";
import hre, {ethers, upgrades} from "hardhat";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {
    Minter,
    BoostStablecoin,
    MockERC20,
    ISolidlyV3Pool,
    ISolidlyV3Factory,
    SolidlyV3LiquidityAMO,
} from "../typechain-types";
import {bigint} from "hardhat/internal/core/params/argumentTypes";

describe("SolidlyV3AMO", function () {
    let solidlyV3AMO: SolidlyV3LiquidityAMO;
    let boost: BoostStablecoin;
    let testUSD: MockERC20;
    let minter: Minter;
    let pool: ISolidlyV3Pool;
    let poolFactory: ISolidlyV3Factory;
    let admin: SignerWithAddress;
    let treasuryVault: SignerWithAddress;
    let setter: SignerWithAddress;
    let amo: SignerWithAddress;
    let withdrawer: SignerWithAddress;
    let pauser: SignerWithAddress;
    let unpauser: SignerWithAddress;
    let boostMinter: SignerWithAddress;
    let user: SignerWithAddress;

    let setterRole: any;
    let amoRole: any;
    let withdrawerRole: any;
    let pauserRole: any;
    let unpauserRole: any;

    const V3_POOL_FACTORY_ADDRESS = "0x70Fe4a44EA505cFa3A57b95cF2862D4fd5F0f687";
    const MIN_SQRT_RATIO = BigInt('4295128739'); // Minimum sqrt price ratio
    const MAX_SQRT_RATIO = BigInt('1461446703485210103287273052203988822378723970342'); // Maximum sqrt price ratio
    let sqrtPriceX96: bigint;
    const liquidity = ethers.parseUnits("10000000", 12); // ~10M
    const boostDesired = ethers.parseUnits("11000000", 18); // 10M
    const collateralDesired = ethers.parseUnits("11000000", 6); // 10M
    const boostMin4Liqudity = ethers.parseUnits("9990000", 18);
    const collateralMin4Liqudity = ethers.parseUnits("9990000", 6);
    const tickLower = -887200;
    const tickUpper = 887200;
    const poolFee = 100;
    const price = "1";

    beforeEach(async function () {
        [admin, treasuryVault, setter, amo, withdrawer, pauser, unpauser, boostMinter, user] = await ethers.getSigners();

        // Deploy the actual contracts using deployProxy
        const BoostFactory = await ethers.getContractFactory("BoostStablecoin");
        boost = (await upgrades.deployProxy(BoostFactory, [admin.address])) as unknown as BoostStablecoin;
        await boost.waitForDeployment();

        const MockErc20Factory = await ethers.getContractFactory("MockERC20");
        testUSD = await MockErc20Factory.deploy("USD", "USD", 6);
        await testUSD.waitForDeployment();

        const MinterFactory = await ethers.getContractFactory("Minter");
        minter = (await upgrades.deployProxy(MinterFactory, [await boost.getAddress(), await testUSD.getAddress(), await admin.getAddress()])) as unknown as Minter;
        await minter.waitForDeployment();

        // Mint Boost and TestUSD
        await boost.grantRole(await boost.MINTER_ROLE(), await minter.getAddress());
        await boost.grantRole(await boost.MINTER_ROLE(), boostMinter.address);
        await boost.connect(boostMinter).mint(admin.address, boostDesired);
        await testUSD.connect(boostMinter).mint(admin.address, collateralDesired);

        // Create Pool
        poolFactory = await ethers.getContractAt("ISolidlyV3Factory", V3_POOL_FACTORY_ADDRESS);
        const tickSpacing = await poolFactory.feeAmountTickSpacing(poolFee);
        await poolFactory.createPool(await boost.getAddress(), await testUSD.getAddress(), poolFee);
        const pool_address = await poolFactory.getPool(await boost.getAddress(), await testUSD.getAddress(), tickSpacing);

        if ((await boost.getAddress()).toLowerCase() < (await testUSD.getAddress()).toLowerCase()) {
            sqrtPriceX96 = BigInt(Math.floor(Math.sqrt(Number((BigInt(price) * BigInt(2 ** 192)) / BigInt(10 ** 12)))));
        } else {
            sqrtPriceX96 = BigInt(Math.floor(Math.sqrt(Number((BigInt(price) * BigInt(2 ** 192)) * BigInt(10 ** 12)))));
        }
        pool = await ethers.getContractAt("ISolidlyV3Pool", pool_address);
        await pool.initialize(sqrtPriceX96);

        // Deploy SolidlyV3AMO using upgrades.deployProxy
        const SolidlyV3LiquidityAMOFactory = await ethers.getContractFactory("SolidlyV3LiquidityAMO");
        const args = [
            admin.address,
            await boost.getAddress(),
            await testUSD.getAddress(),
            pool_address,
            await minter.getAddress(),
            treasuryVault.address,
            tickLower,
            tickUpper,
            sqrtPriceX96,
            ethers.toBigInt("1100000"), // boostMultiplier
            100000, // validRangeRatio
            990000, // validRemovingRatio
            100000, // dryPowderRatio
            990000, // usdUsageRatio
            ethers.parseUnits("0.95", 6), // boostLowerPriceSell
            ethers.parseUnits("1.05", 6), // boostUpperPriceBuy
        ];
        solidlyV3AMO = (await upgrades.deployProxy(SolidlyV3LiquidityAMOFactory, args)) as unknown as SolidlyV3LiquidityAMO;
        await solidlyV3AMO.waitForDeployment();

        // Provide liquidity
        await boost.approve(pool_address, boostDesired);
        await testUSD.approve(pool_address, collateralDesired);

        let amount0Min, amount1Min;
        if ((await boost.getAddress()).toLowerCase() < (await testUSD.getAddress()).toLowerCase()) {
            amount0Min = boostMin4Liqudity;
            amount1Min = collateralMin4Liqudity;
        } else {
            amount1Min = boostMin4Liqudity;
            amount0Min = collateralMin4Liqudity;
        }
        await pool.mint(
            await solidlyV3AMO.getAddress(),
            tickLower,
            tickUpper,
            liquidity,
            amount0Min,
            amount1Min,
            Math.floor(Date.now() / 1000) + 60 * 10
        );

        // Grant Roles
        setterRole = await solidlyV3AMO.SETTER_ROLE();
        amoRole = await solidlyV3AMO.AMO_ROLE();
        withdrawerRole = await solidlyV3AMO.WITHDRAWER_ROLE();
        pauserRole = await solidlyV3AMO.PAUSER_ROLE();
        unpauserRole = await solidlyV3AMO.UNPAUSER_ROLE();

        await solidlyV3AMO.grantRole(setterRole, setter.address);
        await solidlyV3AMO.grantRole(amoRole, amo.address);
        await solidlyV3AMO.grantRole(withdrawerRole, withdrawer.address);
        await solidlyV3AMO.grantRole(pauserRole, pauser.address);
        await solidlyV3AMO.grantRole(unpauserRole, unpauser.address);
        await minter.grantRole(await minter.AMO_ROLE(), await solidlyV3AMO.getAddress());
    });

    it("should initialize with correct parameters", async function () {
        expect(await solidlyV3AMO.boost()).to.equal(await boost.getAddress());
        expect(await solidlyV3AMO.usd()).to.equal(await testUSD.getAddress());
        expect(await solidlyV3AMO.pool()).to.equal(await pool.getAddress());
        expect(await solidlyV3AMO.boostMinter()).to.equal(await minter.getAddress());
    });

    it("should only allow SETTER_ROLE to call setParams", async function () {
        // Try calling setParams without SETTER_ROLE
        await expect(
            solidlyV3AMO.connect(user).setParams(
                ethers.toBigInt("1100000"),
                100000,
                990000,
                100000,
                990000,
                ethers.parseUnits("0.95", 6),
                ethers.parseUnits("1.05", 6)
            )
        ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${setterRole}`);

        // Call setParams with SETTER_ROLE
        await expect(
            solidlyV3AMO.connect(setter).setParams(
                ethers.toBigInt("1100000"),
                100000,
                990000,
                100000,
                990000,
                ethers.parseUnits("0.95", 6),
                ethers.parseUnits("1.05", 6)
            )
        ).to.emit(solidlyV3AMO, "ParamsSet");
    });

    it("should only allow AMO_ROLE to call mintAndSellBoost", async function () {
        let limitSqrtPriceX96: bigint;
        if ((await boost.getAddress()).toLowerCase() < (await testUSD.getAddress()).toLowerCase()) {
            limitSqrtPriceX96 = BigInt(Math.floor(Math.sqrt(Number((BigInt("2") * BigInt(2 ** 192)) / BigInt(10 ** 12)))));
        } else {
            limitSqrtPriceX96 = BigInt(Math.floor(Math.sqrt(Number((BigInt("2") * BigInt(2 ** 192)) * BigInt(10 ** 12)))));
        }
        const usdToBuy = ethers.parseUnits("1000000", 6);
        await testUSD.connect(admin).mint(user.address, usdToBuy);
        await testUSD.approve(await pool.getAddress(), usdToBuy);
        await pool.swap(
            await user.getAddress(),
            (await boost.getAddress()).toLowerCase() > (await testUSD.getAddress()).toLowerCase(),
            usdToBuy,
            limitSqrtPriceX96,
            usdToBuy,
            Math.floor(Date.now() / 1000) + 60 * 10
        );

        const boostAmount = ethers.parseUnits("990000", 18);
        const usdAmount = ethers.parseUnits("990000", 6);

        await expect(
            solidlyV3AMO.connect(user).mintAndSellBoost(
                boostAmount,
                usdAmount,
                Math.floor(Date.now() / 1000) + 60 * 10
            )
        ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${amoRole}`);

        await expect(
            solidlyV3AMO.connect(amo).mintAndSellBoost(
                boostAmount,
                usdAmount,
                Math.floor(Date.now() / 1000) + 60 * 10
            )
        ).to.emit(solidlyV3AMO, "MintSell");
        expect(await solidlyV3AMO.boostPrice()).to.be.approximately(ethers.parseUnits(price, 6), 10)
    });

    it("should only allow AMO_ROLE to call addLiquidity", async function () {
        const usdAmountToAdd = ethers.parseUnits("1000", 6);
        const boostMinAmount = ethers.parseUnits("900", 18);
        const usdMinAmount = ethers.parseUnits("900", 6);
        await testUSD.connect(admin).mint(await solidlyV3AMO.getAddress(), usdAmountToAdd);

        await expect(
            solidlyV3AMO.connect(user).addLiquidity(
                usdAmountToAdd,
                boostMinAmount,
                usdMinAmount,
                Math.floor(Date.now() / 1000) + 60 * 10
            )
        ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${amoRole}`);

        await expect(
            solidlyV3AMO.connect(amo).addLiquidity(
                usdAmountToAdd,
                boostMinAmount,
                usdMinAmount,
                Math.floor(Date.now() / 1000) + 60 * 10
            )
        ).to.emit(solidlyV3AMO, "AddLiquidity");
    });

    it("should only allow PAUSER_ROLE to pause and UNPAUSER_ROLE to unpause", async function () {
        await expect(solidlyV3AMO.connect(pauser).pause()).to.emit(solidlyV3AMO, "Paused").withArgs(pauser.address);

        await expect(
            solidlyV3AMO.connect(amo).mintAndSellBoost(
                ethers.parseUnits("1000", 18),
                ethers.parseUnits("950", 6),
                Math.floor(Date.now() / 1000) + 60 * 10
            )
        ).to.be.revertedWith("Pausable: paused");

        await expect(solidlyV3AMO.connect(unpauser).unpause()).to.emit(solidlyV3AMO, "Unpaused").withArgs(unpauser.address);
    });

    it("should allow WITHDRAWER_ROLE to withdraw ERC20 tokens", async function () {
        // Transfer some tokens to the contract
        await testUSD.connect(user).mint(await solidlyV3AMO.getAddress(), ethers.parseUnits("1000", 6));

        // Try withdrawing tokens without WITHDRAWER_ROLE
        await expect(
            solidlyV3AMO.connect(user).withdrawERC20(await testUSD.getAddress(), ethers.parseUnits("1000", 6), user.address)
        ).to.be.revertedWith(`AccessControl: account ${user.address.toLowerCase()} is missing role ${withdrawerRole}`);

        // Withdraw tokens with WITHDRAWER_ROLE
        await solidlyV3AMO.connect(withdrawer).withdrawERC20(await testUSD.getAddress(), ethers.parseUnits("1000", 6), user.address);
        const usdBalanceOfUser = await testUSD.balanceOf(await user.getAddress());
        expect(usdBalanceOfUser).to.be.equal(ethers.parseUnits("1000", 6));
    });

    it("should execute public mintSellFarm when price above 1", async function () {
        let limitSqrtPriceX96: bigint;
        const boostAddress = (await boost.getAddress()).toLowerCase();
        const testUSDAddress = (await testUSD.getAddress()).toLowerCase();
        const zeroForOne = boostAddress > testUSDAddress;
        const slot0 = await pool.slot0();
        const currentSqrtPriceX96 = slot0.sqrtPriceX96;
        if (zeroForOne) {
            limitSqrtPriceX96 = MIN_SQRT_RATIO + BigInt(10);
        } else {
            limitSqrtPriceX96 = MAX_SQRT_RATIO - BigInt(10);
        }
        const usdToBuy = ethers.parseUnits("100000", 6);
        await testUSD.connect(admin).mint(user.address, usdToBuy);
        await testUSD.approve(await pool.getAddress(), usdToBuy);
        await pool.swap(
            await user.getAddress(),
            zeroForOne,
            usdToBuy,
            limitSqrtPriceX96,
            usdToBuy,
            Math.floor(Date.now() / 1000) + 60 * 10
        );
        expect(await solidlyV3AMO.boostPrice()).to.be.gt(ethers.parseUnits(price, 6))
        await expect(solidlyV3AMO.connect(user).mintSellFarm()).to.be.emit(solidlyV3AMO, "PublicMintSellFarmExecuted");
        expect(await solidlyV3AMO.boostPrice()).to.be.approximately(ethers.parseUnits(price, 6), 10)
    });

    it("should correctly return boostPrice", async function () {
        expect(await solidlyV3AMO.boostPrice()).to.be.approximately(ethers.parseUnits(price, 6), 10);
    });

    it("should revert when invalid parameters are set", async function () {
        await expect(
            solidlyV3AMO.connect(setter).setParams(
                ethers.toBigInt("1100000"),
                2000000, // invalid validRangeRatio > FACTOR (10^6)
                990000,
                100000,
                990000,
                ethers.parseUnits("0.95", 6),
                ethers.parseUnits("1.05", 6)
            )
        ).to.be.revertedWithCustomError(solidlyV3AMO, "InvalidRatioValue");
    });

    it("should correctly return liquidityForUsd and liquidityForBoost", async function () {
        const usdInPool = await testUSD.balanceOf(await pool.getAddress())
        const liquidityUsd = await solidlyV3AMO.liquidityForUsd(1);
        expect(liquidityUsd).to.be.equal(liquidity / usdInPool);

        const boostInPool = await boost.balanceOf(await pool.getAddress())
        const liquidityBoost = await solidlyV3AMO.liquidityForBoost(1);
        expect(liquidityBoost).to.be.equal(liquidity / boostInPool);
    });

    it("should return position correctly", async function () {
        const position = await solidlyV3AMO.position();
        expect(position._liquidity).to.be.equal(liquidity);
        expect(position.boostOwed).to.be.equal(0);
        expect(position.usdOwed).to.be.equal(0);
    });

    it("should only allow SETTER_ROLE to setVault", async function () {
        await expect(solidlyV3AMO.connect(user).setVault(user.address)).to.be.revertedWith(
            `AccessControl: account ${user.address.toLowerCase()} is missing role ${setterRole}`
        );

        await expect(solidlyV3AMO.connect(setter).setVault(user.address)).to.emit(solidlyV3AMO, "VaultSet");
    });

    it("should only allow SETTER_ROLE to setTickBounds", async function () {
        await expect(solidlyV3AMO.connect(user).setTickBounds(-100, 100)).to.be.revertedWith(
            `AccessControl: account ${user.address.toLowerCase()} is missing role ${setterRole}`
        );

        await expect(solidlyV3AMO.connect(setter).setTickBounds(-100, 100)).to.emit(solidlyV3AMO, "TickBoundsSet");
    });

    it("should only allow SETTER_ROLE to setTargetSqrtPriceX96", async function () {
        const validSqrtPriceX96 = ethers.toBigInt("79228162514264337593543950336"); // sqrt(1) * 2^96
        await expect(solidlyV3AMO.connect(user).setTargetSqrtPriceX96(validSqrtPriceX96)).to.be.revertedWith(
            `AccessControl: account ${user.address.toLowerCase()} is missing role ${setterRole}`
        );

        await expect(solidlyV3AMO.connect(setter).setTargetSqrtPriceX96(validSqrtPriceX96)).to.emit(
            solidlyV3AMO,
            "TargetSqrtPriceX96Set"
        );
    });
});
