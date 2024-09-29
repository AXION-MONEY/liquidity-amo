import {ethers, upgrades} from "hardhat";
import {expect} from "chai";
import {Minter, BOOSTStablecoin, MockERC20} from "../typechain-types"; // Adjust the import paths according to your setup
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

describe("Minter Contract Tests", function () {
    let MockERC20Contract: ethers.ContractFactory;

    let minterContract: Minter;
    let collateralToken: MockERC20;
    let boostToken: BOOSTStablecoin;

    let owner: SignerWithAddress;
    let admin: SignerWithAddress;
    let treasury: SignerWithAddress;
    let pauser: SignerWithAddress;
    let unpauser: SignerWithAddress;
    let minterAddress: SignerWithAddress;
    let amo: SignerWithAddress;
    let user: SignerWithAddress;
    let withdrawer: SignerWithAddress;

    let pauserRole: any;
    let unpauserRole: any;
    let minterRole: any;
    let adminRole: any;
    let AMORole: any;
    let withdrawTokenRole: any;

    beforeEach(async function () {
        // Get signers
        [owner, admin, treasury, pauser, unpauser, minterAddress, amo, withdrawer, user] = await ethers.getSigners();

        // Deploy the mock ERC20 token for collateral
        MockERC20Contract = await ethers.getContractFactory("MockERC20");
        collateralToken = await MockERC20Contract.deploy("Collateral Token", "COL", 6);
        await collateralToken.waitForDeployment();
        // Deploy the BOOSTStablecoin contract
        const BOOSTStablecoin = await ethers.getContractFactory('BoostStablecoin', owner);
        boostToken = await upgrades.deployProxy(BOOSTStablecoin, [admin.address], {initializer: "initialize"});
        await boostToken.waitForDeployment();

        // Deploy the Minter contract
        const Minter = await ethers.getContractFactory("Minter", owner);
        minterContract = (await upgrades.deployProxy(Minter, [
            await boostToken.getAddress(),
            await collateralToken.getAddress(),
            treasury.address,
        ], {initializer: "initialize"}));
        await minterContract.waitForDeployment();

        pauserRole = await minterContract.PAUSER_ROLE();
        unpauserRole = await minterContract.UNPAUSER_ROLE();
        minterRole = await minterContract.MINTER_ROLE();
        adminRole = await minterContract.ADMIN_ROLE();
        AMORole = await minterContract.AMO_ROLE();
        withdrawTokenRole = await minterContract.WITHDRAWER_ROLE();

        // Grant roles
        await minterContract.connect(owner).grantRole(pauserRole, pauser.address);
        await minterContract.connect(owner).grantRole(unpauserRole, unpauser.address);
        await minterContract.connect(owner).grantRole(minterRole, minterAddress.address);
        await minterContract.connect(owner).grantRole(adminRole, admin.address);
        await minterContract.connect(owner).grantRole(AMORole, amo.address);
        await minterContract.connect(owner).grantRole(withdrawTokenRole, withdrawer);

        await boostToken.connect(admin).grantRole(await boostToken.MINTER_ROLE(), minterContract.getAddress());
    });

    describe('Initializing', function () {
        it("Should set initial state correctly", async function () {
            expect(await minterContract.boostAddress()).to.equal(await boostToken.getAddress());
            expect(await minterContract.collateralAddress()).to.equal(await collateralToken.getAddress());
            expect(await minterContract.treasury()).to.equal(await treasury.address);
        });
    });

    describe('Setting', function () {
        it("Should allow setting tokens addresses by admin", async function () {
            const newCollateralToken = await MockERC20Contract.deploy("New Collateral Token", "NEWCOL", 6);
            await newCollateralToken.waitForDeployment();
            await minterContract.connect(admin).setTokens(boostToken.getAddress(), newCollateralToken.getAddress());
            expect(await minterContract.collateralAddress()).to.equal(await newCollateralToken.getAddress());
        });

        it("Should allow setting the treasury address by admin", async function () {
            expect(await minterContract.treasury()).to.equal(treasury.address);
            await minterContract.connect(admin).setTreasury(user.address);
            expect(await minterContract.treasury()).to.equal(user.address);
        });
    });

    describe('Minting', function () {
        it("Should allow minter to mint", async function () {
            expect(await boostToken.balanceOf(user.address)).to.equal(0);
            const mintAmount = ethers.parseUnits("1", 18);
            const collateralAmount = ethers.parseUnits("1", 6);

            expect(await collateralToken.balanceOf(minterAddress.address)).to.equal(0);
            await collateralToken.mint(minterAddress.address, collateralAmount);
            expect(await collateralToken.balanceOf(minterAddress.address)).to.equal(collateralAmount);
            await collateralToken.connect(minterAddress).approve(minterContract.getAddress(), collateralAmount);

            await minterContract.connect(minterAddress).mint(minterAddress.address, mintAmount);
            expect(await boostToken.balanceOf(minterAddress.address)).to.equal(mintAmount);
            expect(await collateralToken.balanceOf(minterAddress.address)).to.equal(0);
        });

        it("Should not allow minter to mint when paused", async function () {
            expect(await boostToken.balanceOf(user.address)).to.equal(0);
            const mintAmount = ethers.parseUnits("1", 18);

            expect(await collateralToken.balanceOf(minterAddress.address)).to.equal(0);
            await collateralToken.mint(minterAddress.address, mintAmount);
            expect(await collateralToken.balanceOf(minterAddress.address)).to.equal(mintAmount);
            await collateralToken.connect(minterAddress).approve(minterContract.getAddress(), mintAmount);

            await minterContract.connect(pauser).pause();

            await expect(minterContract.connect(minterAddress).mint(minterAddress.address, mintAmount)).to.be.revertedWith("Pausable: paused");
            expect(await boostToken.balanceOf(minterAddress.address)).to.equal(0);
            expect(await collateralToken.balanceOf(minterAddress.address)).to.equal(mintAmount);
        });

        it("Should allow AMO to plotocol mint", async function () {
            expect(await boostToken.balanceOf(user.address)).to.equal(0);
            const mintAmount = ethers.parseUnits("1", 18);
            await minterContract.connect(amo).protocolMint(user.address, mintAmount);
            expect(await boostToken.balanceOf(user.address)).to.equal(mintAmount);
        });

        it("Should not allow AMO to protocol mint when paused", async function () {
            expect(await boostToken.balanceOf(user.address)).to.equal(0);
            const mintAmount = ethers.parseUnits("1", 18);
            await minterContract.connect(pauser).pause();
            await expect(minterContract.connect(amo).protocolMint(user.address, mintAmount)).to.be.revertedWith("Pausable: paused");
            expect(await boostToken.balanceOf(user.address)).to.equal(0);
        });

        it("Should not allow others to protocol mint", async function () {
            expect(await boostToken.balanceOf(user.address)).to.equal(0);
            const mintAmount = ethers.parseUnits("1", 18);
            let reverteMessage = `AccessControl: account ${owner.address.toLowerCase()} is missing role ${AMORole}`;
            await expect(minterContract.connect(owner).protocolMint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${admin.address.toLowerCase()} is missing role ${AMORole}`;
            await expect(minterContract.connect(admin).protocolMint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${minterAddress.address.toLowerCase()} is missing role ${AMORole}`;
            await expect(minterContract.connect(minterAddress).protocolMint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${pauser.address.toLowerCase()} is missing role ${AMORole}`;
            await expect(minterContract.connect(pauser).protocolMint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${unpauser.address.toLowerCase()} is missing role ${AMORole}`;
            await expect(minterContract.connect(unpauser).protocolMint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${withdrawer.address.toLowerCase()} is missing role ${AMORole}`;
            await expect(minterContract.connect(withdrawer).protocolMint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${user.address.toLowerCase()} is missing role ${AMORole}`;
            await expect(minterContract.connect(user).protocolMint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            expect(await boostToken.balanceOf(user.address)).to.equal(0);
        });

        it("Should not allow others to mint", async function () {
            expect(await boostToken.balanceOf(user.address)).to.equal(0);
            const mintAmount = ethers.parseUnits("1", 18);
            let reverteMessage = `AccessControl: account ${owner.address.toLowerCase()} is missing role ${minterRole}`;
            await expect(minterContract.connect(owner).mint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${admin.address.toLowerCase()} is missing role ${minterRole}`;
            await expect(minterContract.connect(admin).mint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${amo.address.toLowerCase()} is missing role ${minterRole}`;
            await expect(minterContract.connect(amo).mint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${pauser.address.toLowerCase()} is missing role ${minterRole}`;
            await expect(minterContract.connect(pauser).mint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${unpauser.address.toLowerCase()} is missing role ${minterRole}`;
            await expect(minterContract.connect(unpauser).mint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${withdrawer.address.toLowerCase()} is missing role ${minterRole}`;
            await expect(minterContract.connect(withdrawer).mint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${user.address.toLowerCase()} is missing role ${minterRole}`;
            await expect(minterContract.connect(user).mint(user.address, mintAmount)).to.be.revertedWith(reverteMessage);

            expect(await boostToken.balanceOf(user.address)).to.equal(0);
        });
    });

    describe('Pausing and Unpausing', function () {
        it('Should pause and unpause the contract', async function () {
            await minterContract.connect(pauser).pause();

            expect(await minterContract.paused()).to.equal(true);

            await minterContract.connect(unpauser).unpause();
            expect(await minterContract.paused()).to.equal(false);
        });
    });

    describe('Withdraw', function () {
        it('Should allow withdrawer to withdraw token', async function () {
            const newToken = await MockERC20Contract.deploy("New Token", "Token", 6);
            await newToken.waitForDeployment();

            const mintAmount = ethers.parseUnits("100", 6);
            await newToken.mint(minterContract.getAddress(), mintAmount);
            expect(await newToken.balanceOf(minterContract.getAddress())).to.be.equal(mintAmount);

            expect(await newToken.balanceOf(treasury.address)).to.be.equal(0);
            await minterContract.connect(withdrawer).withdrawToken(newToken.getAddress(), mintAmount);
            expect(await newToken.balanceOf(treasury.address)).to.be.equal(mintAmount);
        });

        it('Should not allow others to withdraw token', async function () {
            const newToken = await MockERC20Contract.deploy("New Token", "Token", 6);
            await newToken.waitForDeployment();

            const mintAmount = ethers.parseUnits("100", 6);
            await newToken.mint(minterContract.getAddress(), mintAmount);
            expect(await newToken.balanceOf(minterContract.getAddress())).to.be.equal(mintAmount);
            expect(await newToken.balanceOf(treasury.address)).to.be.equal(0);

            let reverteMessage = `AccessControl: account ${owner.address.toLowerCase()} is missing role ${withdrawTokenRole}`;
            await expect(minterContract.connect(owner).withdrawToken(newToken.getAddress(), mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${admin.address.toLowerCase()} is missing role ${withdrawTokenRole}`;
            await expect(minterContract.connect(admin).withdrawToken(newToken.getAddress(), mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${pauser.address.toLowerCase()} is missing role ${withdrawTokenRole}`;
            await expect(minterContract.connect(pauser).withdrawToken(newToken.getAddress(), mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${unpauser.address.toLowerCase()} is missing role ${withdrawTokenRole}`;
            await expect(minterContract.connect(unpauser).withdrawToken(newToken.getAddress(), mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${amo.address.toLowerCase()} is missing role ${withdrawTokenRole}`;
            await expect(minterContract.connect(amo).withdrawToken(newToken.getAddress(), mintAmount)).to.be.revertedWith(reverteMessage);

            reverteMessage = `AccessControl: account ${user.address.toLowerCase()} is missing role ${withdrawTokenRole}`;
            await expect(minterContract.connect(user).withdrawToken(newToken.getAddress(), mintAmount)).to.be.revertedWith(reverteMessage);
            expect(await newToken.balanceOf(treasury.address)).to.be.equal(0);
        });
    });

});