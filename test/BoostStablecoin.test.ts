import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { BoostStablecoin } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("BOOSTStablecoin Tests", function () {
  let boostStablecoin: BoostStablecoin;
  let admin: SignerWithAddress;
  let pauser: SignerWithAddress;
  let unpauser: SignerWithAddress;
  let minter: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let pauserRole: any, unpauserRole: any, minterRole: any;
  const mintAmount = ethers.parseEther("100");

  beforeEach(async function () {
    [admin, pauser, unpauser, minter, user1, user2] = await ethers.getSigners();

    // Deploy the BOOSTStablecoin contract
    const BOOSTStablecoin = await ethers.getContractFactory("BoostStablecoin", admin);
    boostStablecoin = (await upgrades.deployProxy(BOOSTStablecoin, [admin.address], {
      initializer: "initialize"
    })) as unknown as BoostStablecoin;
    await boostStablecoin.waitForDeployment();

    pauserRole = await boostStablecoin.PAUSER_ROLE();
    unpauserRole = await boostStablecoin.UNPAUSER_ROLE();
    minterRole = await boostStablecoin.MINTER_ROLE();

    // Grant roles
    await boostStablecoin.connect(admin).grantRole(pauserRole, pauser.address);
    await boostStablecoin.connect(admin).grantRole(unpauserRole, unpauser.address);
    await boostStablecoin.connect(admin).grantRole(minterRole, minter.address);
  });

  describe("Minting", function () {
    it("Should mint tokens to the specified address by minter", async function () {
      await boostStablecoin.connect(minter).mint(user1.address, mintAmount);
      expect(await boostStablecoin.balanceOf(user1.address)).to.equal(mintAmount);
    });

    it("Should revert token mint when paused", async function () {
      await boostStablecoin.connect(pauser).pause();

      await expect(boostStablecoin.connect(minter).mint(user1.address, mintAmount)).to.be.revertedWithCustomError(
        boostStablecoin,
        "EnforcedPause"
      );
      expect(await boostStablecoin.balanceOf(user1.address)).to.equal("0");
    });

    it("Should NOT mint tokens by pauser", async function () {
      await expect(boostStablecoin.connect(pauser).mint(user1.address, mintAmount))
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(pauser.address, minterRole);
      expect(await boostStablecoin.balanceOf(user1.address)).to.equal("0");
    });

    it("Should NOT mint tokens by unpauser", async function () {
      await expect(boostStablecoin.connect(unpauser).mint(user1.address, mintAmount))
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(unpauser.address, minterRole);
      expect(await boostStablecoin.balanceOf(user1.address)).to.equal("0");
    });

    it("Should NOT mint tokens by owner", async function () {
      await expect(boostStablecoin.connect(admin).mint(user1.address, mintAmount))
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(admin.address, minterRole);
      expect(await boostStablecoin.balanceOf(user1.address)).to.equal("0");
    });
  });

  describe("Burning", function () {
    beforeEach(async function () {
      await boostStablecoin.connect(minter).mint(user1.address, 1000);
    });

    it("Should burn tokens from own address", async function () {
      await boostStablecoin.connect(user1).burn(200);
      expect(await boostStablecoin.balanceOf(user1.address)).equal(800);
    });

    it("Should burn tokens from other address when allowance is sufficient", async function () {
      await boostStablecoin.connect(user1).approve(user2.address, 300);
      await boostStablecoin.connect(user2).burnFrom(user1.address, 300);
      expect(await boostStablecoin.balanceOf(user1.address)).equal(700);
    });

    it("Should NOT burn tokens from other address when allowance is insufficient", async function () {
      await boostStablecoin.connect(user1).approve(user2.address, 300);
      await expect(boostStablecoin.connect(user2).burnFrom(user1.address, 301))
        .to.be.revertedWithCustomError(boostStablecoin, "ERC20InsufficientAllowance")
        .withArgs(user2.address, 300, 301);
    });
  });

  describe("Pausing and Unpausing", function () {
    it("Should pause and unpause the contract", async function () {
      await boostStablecoin.connect(pauser).pause();

      expect(await boostStablecoin.paused()).to.equal(true);

      await boostStablecoin.connect(unpauser).unpause();
      expect(await boostStablecoin.paused()).to.equal(false);
    });

    it("Should NOT pause and unpause by other than pauser and unpauser", async function () {
      await expect(boostStablecoin.connect(admin).pause())
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(admin.address, pauserRole);

      await expect(boostStablecoin.connect(minter).pause())
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(minter.address, pauserRole);

      await expect(boostStablecoin.connect(unpauser).pause())
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(unpauser.address, pauserRole);

      await boostStablecoin.connect(pauser).pause();

      expect(await boostStablecoin.paused()).to.equal(true);

      await expect(boostStablecoin.connect(admin).unpause())
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(admin.address, unpauserRole);

      await expect(boostStablecoin.connect(minter).unpause())
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(minter.address, unpauserRole);

      await expect(boostStablecoin.connect(pauser).unpause())
        .to.be.revertedWithCustomError(boostStablecoin, "AccessControlUnauthorizedAccount")
        .withArgs(pauser.address, unpauserRole);
    });
  });

  describe("Token Transfer", function () {
    it("Should transfers tokens", async function () {
      const transferAmount = ethers.parseEther("1");
      await boostStablecoin.connect(minter).mint(user1.address, mintAmount);

      await boostStablecoin.connect(user1).transfer(user2.address, transferAmount);
      expect(await boostStablecoin.balanceOf(user2.address)).to.equal(transferAmount);
      expect(await boostStablecoin.balanceOf(user1.address)).to.equal(mintAmount - transferAmount);
    });

    it("Should revert token transfers when paused", async function () {
      await boostStablecoin.connect(minter).mint(user1.address, mintAmount);

      await boostStablecoin.connect(pauser).pause();

      await expect(
        boostStablecoin.connect(user1).transfer(user2.address, ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(boostStablecoin, "EnforcedPause");
      expect(await boostStablecoin.balanceOf(user2.address)).to.equal("0");
    });
  });
});
