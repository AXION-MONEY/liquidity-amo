import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Ion } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("Ion Tests", function () {
  let ion: Ion;
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

    // Deploy the Ion contract
    const Ion = await ethers.getContractFactory("Ion", admin);
    ion = await upgrades.deployProxy(Ion, ["Ion", "ION", admin.address], {
      initializer: "initialize"
    });
    await ion.waitForDeployment();

    pauserRole = await ion.PAUSER_ROLE();
    unpauserRole = await ion.UNPAUSER_ROLE();
    minterRole = await ion.MINTER_ROLE();

    // Grant roles
    await ion.connect(admin).grantRole(pauserRole, pauser.address);
    await ion.connect(admin).grantRole(unpauserRole, unpauser.address);
    await ion.connect(admin).grantRole(minterRole, minter.address);
  });

  describe("Minting", function () {
    it("Should mint tokens to the specified address by minter", async function () {
      await ion.connect(minter).mint(user1.address, mintAmount);
      expect(await ion.balanceOf(user1.address)).to.equal(mintAmount);
    });

    it("Should revert token mint when paused", async function () {
      await ion.connect(pauser).pause();

      await expect(ion.connect(minter).mint(user1.address, mintAmount)).to.be.revertedWithCustomError(
        ion,
        "EnforcedPause"
      );
      expect(await ion.balanceOf(user1.address)).to.equal("0");
    });

    it("Should NOT mint tokens by pauser", async function () {
      await expect(ion.connect(pauser).mint(user1.address, mintAmount))
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(pauser.address, minterRole);
      expect(await ion.balanceOf(user1.address)).to.equal("0");
    });

    it("Should NOT mint tokens by unpauser", async function () {
      await expect(ion.connect(unpauser).mint(user1.address, mintAmount))
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(unpauser.address, minterRole);
      expect(await ion.balanceOf(user1.address)).to.equal("0");
    });

    it("Should NOT mint tokens by owner", async function () {
      await expect(ion.connect(admin).mint(user1.address, mintAmount))
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(admin.address, minterRole);
      expect(await ion.balanceOf(user1.address)).to.equal("0");
    });
  });

  describe("Burning", function () {
    beforeEach(async function () {
      await ion.connect(minter).mint(user1.address, 1000);
    });

    it("Should burn tokens from own address", async function () {
      await ion.connect(user1).burn(200);
      expect(await ion.balanceOf(user1.address)).equal(800);
    });

    it("Should burn tokens from other address when allowance is sufficient", async function () {
      await ion.connect(user1).approve(user2.address, 300);
      await ion.connect(user2).burnFrom(user1.address, 300);
      expect(await ion.balanceOf(user1.address)).equal(700);
    });

    it("Should NOT burn tokens from other address when allowance is insufficient", async function () {
      await ion.connect(user1).approve(user2.address, 300);
      await expect(ion.connect(user2).burnFrom(user1.address, 301))
        .to.be.revertedWithCustomError(ion, "ERC20InsufficientAllowance")
        .withArgs(user2.address, 300, 301);
    });
  });

  describe("Pausing and Unpausing", function () {
    it("Should pause and unpause the contract", async function () {
      await ion.connect(pauser).pause();

      expect(await ion.paused()).to.equal(true);

      await ion.connect(unpauser).unpause();
      expect(await ion.paused()).to.equal(false);
    });

    it("Should NOT pause and unpause by other than pauser and unpauser", async function () {
      await expect(ion.connect(admin).pause())
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(admin.address, pauserRole);

      await expect(ion.connect(minter).pause())
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(minter.address, pauserRole);

      await expect(ion.connect(unpauser).pause())
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(unpauser.address, pauserRole);

      await ion.connect(pauser).pause();

      expect(await ion.paused()).to.equal(true);

      await expect(ion.connect(admin).unpause())
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(admin.address, unpauserRole);

      await expect(ion.connect(minter).unpause())
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(minter.address, unpauserRole);

      await expect(ion.connect(pauser).unpause())
        .to.be.revertedWithCustomError(ion, "AccessControlUnauthorizedAccount")
        .withArgs(pauser.address, unpauserRole);
    });
  });

  describe("Token Transfer", function () {
    it("Should transfers tokens", async function () {
      const transferAmount = ethers.parseEther("1");
      await ion.connect(minter).mint(user1.address, mintAmount);

      await ion.connect(user1).transfer(user2.address, transferAmount);
      expect(await ion.balanceOf(user2.address)).to.equal(transferAmount);
      expect(await ion.balanceOf(user1.address)).to.equal(mintAmount - transferAmount);
    });

    it("Should revert token transfers when paused", async function () {
      await ion.connect(minter).mint(user1.address, mintAmount);

      await ion.connect(pauser).pause();

      await expect(ion.connect(user1).transfer(user2.address, ethers.parseEther("1"))).to.be.revertedWithCustomError(
        ion,
        "EnforcedPause"
      );
      expect(await ion.balanceOf(user2.address)).to.equal("0");
    });
  });
});
