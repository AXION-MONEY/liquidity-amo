# Liquidity AMO: Automated Market Operations for ION Stability & Liquidity Management

## Overview

The **Liquidity AMO (Automated Market Operations)** ensures **ION price stability and deep liquidity** by dynamically
interacting with **multiple AMMs (Automated Market Makers) and stablecoins**. It **mints, sells, adds liquidity, removes
liquidity, and burns ION** based on **real-time market conditions**.

The AMO operates **permissionlessly**, meaning that **anyone** can trigger `mintSellFarm` & `unfarmBuyBurn` to
**rebalance ION’s price**. The system **cannot be manipulated** by flash loans or external actors, ensuring secure and
optimal liquidity management.

The **AMO** supports both **stablecoins** and **Staked Stable Coins (sUSDe, sDAI, ...)** pools. For staked stablecoin
pairs, the AMO executes Automated Market Operations based on data from the price manager contract. This price can be
updated permissionlessly using the **Muon Network**, which retrieves price data from their corresponding contract on the
Mainnet and generates a signature with the necessary data.

---

## Supported DEXs

The AMO interacts with **both Concentrated Liquidity AMMs (CLAMM) and Traditional AMMs (Uniswap V2-style pools)** Any
other DEXs that is use same algorithm as these DEXs can easily add and integrated with AMO Contract:

### CLAMM (Concentrated Liquidity)

- **Uniswap V3**
- **Solidly V3 (CL)**
- **Aerodrome CL**
- **Velodrome CL**
- **Algebra V1.0**
- **Algebra V1.9**
- **Algebra Integral**
- **Ramses V2 (CL)**

### Uniswap V2-Style AMMs

- **Solidly V2**
- **Aerodrome**
- **Velodrome**
- **Equalizer**
- **Thena**

---

## Supported Pair Tokens

The AMO primarily interacts with **stablecoins & staked stable assets** to manage ION’s liquidity:

### Supported Stablecoins

- **USDC** (Circle)
- **DAI** (MakerDAO)
- **FRAX** (Frax Finance)
- **Any Non-Exotic Stable Coin**

### Supported Staked Stablecoins

- **sUSDe** (Ethena Staked USDe)
- **sFRAX** (Frax Staked FRAX)
- **sDAI** (MakerDAO Staked DAI)
- Adding staked stable coins require a few specific steps such as building a dedicated oracle

---

## Core Components

### ION Stable Coin Contract

The ION contract implements an ERC-20 token called "ION," which serves as the foundation of the ION stablecoin project.

#### Key Contract Functions**

| Function                | Description                                                                                |
|-------------------------|--------------------------------------------------------------------------------------------|
| `pause()` & `unpause()` | function can be delegated to a security monitoring firms for automatic responses.          |
| `protocolMint()`        | mint new tokens (using the Minter.Sol contract) and send them to a specified address (to_) |

#### Security & Risk Management

##### Role-Based Access Control (RBAC)

| Role            | Description                            |
|-----------------|----------------------------------------|
| `MINTER_ROLE`   | Can mint new tokens for AMO operations |
| `PAUSER_ROLE`   | Can pause the contract                 |
| `UNPAUSER_ROLE` | CCan unpause the contract              |

##### Token Transfer Guard

This ensures that token transfers are only allowed when the contract is not paused, adding another layer of security.

---

### Liquidity AMO Contracts

#### MasterAMO

MasterAMO is an abstract base contract that defines the shared framework for Automated Market Operations. It provides
the core logic for both mint–sell–farm (when ION is above its target) and unfarm–buy–burn (when ION is below its
target). It also includes utility functions for:

- **Token Scaling (to internal decimals and in relative price to the paired token):**
- **Price Bounds Calculation:**
- **Reserve and Balance Checks:**

##### Key Functions and Patterns:

- **Swap Validation:**
  The modifier `validateSwap(bool ionForPairToken)` and the abstract `_validateSwap` function enforce that swaps occur
  only when market conditions (current price versus target price) are met.
- **Operation Orchestration:**
  The public functions `mintSellFarm` and `unfarmBuyBurn` call the internal implementations defined by the derived
  contracts (V3AMO or V2AMO). These functions:
    - Trigger minting of ION (when over peg) or liquidity removal (when under peg).
    - Interact with DEX routers to swap tokens.
    - Finally, add liquidity or burn ION as required by the current market condition.

#### V3AMO

The V3AMO contract is specialized for concentrated liquidity AMMs (CLAMMs) such as Uniswap V3, Algebra, Ramses CL, and
Solidly CL. It extends MasterAMO by implementing tick-based liquidity management and precise pricing logic using
fixed-point arithmetic.

##### Key Components:

- **TickMath & Liquidity Calculations:**
  The contract uses Uniswap V3’s `TickMath` library to calculate the square root ratios at the tick boundaries (
  `tickLower` and `tickUpper`).
    - The function `_getLiquidityForPairTokenAmount` calculates liquidity available for a given amount of the paired
      token by choosing the correct formula based on the token order.
- **Target Price Conversion:**
  The function `toSqrtPriceX96` converts the target ION price (as determined by the price manager and premium
  adjustments) into the Q64.96 format.

* **Swap Callbacks:**
  V3AMO implements multiple swap callback functions (e.g., `uniswapV3SwapCallback`, `algebraSwapCallback`,
  `solidlyV3SwapCallback`, and `ramsesV2SwapCallback`). All these functions call an internal helper `_swapCallback`,
  which:

    - Verifies that the caller is the expected pool.

    - Decodes swap data to determine whether the operation is a **SELL** (ION is being swapped for the pair token) or a
      **BUY**.

    - Validates the token amounts and price slippage before minting ION or transferring tokens.

* **Mint Callbacks:**
  Similar to swap callbacks, mint callbacks (e.g., `uniswapV3MintCallback`, `algebraMintCallback`, etc.) verify the pool
  caller and then settle token transfers by minting ION or transferring the paired token.

##### Usage Example in V3AMO:

When executing a mint–sell-farm operation:

1. The contract calls `IUniswapV3Pool.swap` with the maximum swap amount and a target sqrt price.
2. During the swap, the pool triggers a callback (`uniswapV3SwapCallback`), which calls `_swapCallback` to validate and
   process the swap.
3. The callback uses Q96-scaled prices to compute liquidity and ensure that the trade respects the tick boundaries and
   slippage limits.
4. After the swap, the contract mints ION tokens (if selling) and adds liquidity with `_addLiquidity`.

#### V2AMO

V2AMO is tailored for Uniswap V2-style AMMs such as Solidly V2, Velodrome, and Equalizer. Unlike V3AMO, it does not use
tick-based liquidity but instead interacts with liquidity gauges and traditional AMM routers.

**Math & Liquidity Operations:**

- **Mint–Sell-Farm Calculation:**
  When ION is above the target price, V2AMO mints ION tokens and sells them to acquire the paired token.

    - The ION minting amount is calculated using the formula:

      ```mathematica
      ionAmountWithoutFee = ((√(pairTokenReserve × ionReserve × FACTOR / ionTargetPrice) − ionReserve) × ionSellRatio) / FACTOR;
      ```

      An additional fee adjustment is added:

      ```mathematica
      ionAmount = (ionAmountWithoutFee × FACTOR) / (FACTOR − poolFee);
      ```

- **Unfarm-Buy-Burn Calculation**

  When ION is below the target price, V2AMO initiates the unfarm–buy–burn process by withdrawing a calculated amount of
  liquidity from the gauge, removing liquidity from the pool, and then swapping to buy ION (which is subsequently
  burned). The key step is determining how much liquidity to unfarm. This is computed using the following formulas:

    * **Calculate the Square Root Ratio:**

      The square root ratio adjusts the reserves based on the target price:

      ```mathematica
      sqrtResRatio = sqrt((FACTOR^2 × pairTokenReserve) / ((ionReserve × ionTargetPrice) / FACTOR))
      ```

    * **Compute the Removal Percentage:**

      This percentage determines the fraction of total liquidity that should be withdrawn, factoring in the pool fee:

      ```mathematica
      removalPercentage = (FACTOR × (FACTOR − sqrtResRatio)) / (FACTOR − ((poolFee × sqrtResRatio) / FACTOR))
      
      ```

    * **Determine the Liquidity to Unfarm:**

      Finally, the liquidity amount is calculated as a proportion of the total LP token supply:

  ```mathematica
  liquidity = totalLp × removalPercentage / FACTOR
  ```

- **Liquidity Addition:**
  After swapping, the contract adds liquidity by:

    - Quoting the required ION amount using the router’s `quoteAddLiquidity` function.
    - Minting the needed ION tokens.
    - Approving the router and calling its `addLiquidity` method to receive LP tokens.
    - Depositing these LP tokens into the liquidity gauge (with an optional token ID if required).

- **Unfarm–Buy–Burn Calculation:**
  For under-peg situations, the contract calculates the proportion of liquidity to remove based on current reserves:

    - It computes a square root ratio (`sqrtResRatio`) that compares the pair token reserve and the ion reserve (
      adjusted by the target price).

    - Then, a `removalPercentage` is determined, which is used to calculate the liquidity amount to be removed from the
      total LP token supply.

    - The liquidity removal is further scaled by the `pairTokenBuyRatio`.

#### Automated Rebalancing Process

1. **Fetch Market Data**
    - Retrieves **ION price** from AMM pools.
    - Queries **Muon Oracles & mainnet staking contracts** for **sUSDe, sFRAX, and sDAI prices**.
    - Update Price on price manager contract if needed.
2. **Decide Action**
    - **If ION > Target Price** → **Mint & Sell ION** → **Provide Liquidity**.
    - **If ION < Target Price** → **Remove Liquidity** → **Buy & Burn ION**.

#### Key Contract Functions

| Function                      | Description                                                                |
|-------------------------------|----------------------------------------------------------------------------|
| `mintSellFarm()`              | Mints & sells ION for stablecoins, then adds liquidity. (✅ Permissionless) |
| `unfarmBuyBurn()`             | Removes liquidity, buys back ION, and burns it. (✅ Permissionless)         |
| `addLiquidity()`              | Adds protocol-owned liquidity to pools. (✅ Permissionless)                 |
| `removeLiquidity()`           | Removes protocol-owned liquidity from pools.                               |
| `setTickBounds()`             | Sets Uniswap V3 tick ranges for liquidity.                                 |
| `ionPriceInPairToken()`       | Fetches the current ION price in the pairToken.                            |
| `ionTargetPriceInPairToken()` | Computes the target price for ION in the pairToken.                        |

#### Security & Risk Management

- **Flash Loan Resistant**
    - Liquidity rebalancing **cannot be exploited** via arbitrage or flash loans.
    - Only **authorized AMO contracts** can execute swaps & liquidity moves.
- **Timelock Governance for Pausing**
    - **AMO operations can only be paused via a Timelock contract**.
    - Ensures **no centralized control over liquidity operations**.

##### Role-Based Access Control (RBAC)

| Role                    | Description                                                                      |
|-------------------------|----------------------------------------------------------------------------------|
| `SETTER_ROLE`           | Can set the contract params & Can add/remove users for bypassing the swap ratio  |
| `PAUSER_ROLE`           | Can pause the contract                                                           |
| `UNPAUSER_ROLE`         | Can unpause the contract                                                         |
| `WITHDRAWER_ROLE`       | Can withdraw ERC20 tokens from the contract & Can remove liquidity from the pool |
| `REWARD_COLLECTOR_ROLE` | Can collect rewards from the gauge (only for V2AMO)                              |

------

### Minter

- **Manages ION minting & burning**.
- **Security measures**:
    - **Only callable by authorized AMO contracts**.
    - **Protocol-owned minting only for liquidity rebalancing**.
    - **Timelock governance for emergency pauses**.

##### Role-Based Access Control (RBAC)

| Role              | Description                                                                    |
|-------------------|--------------------------------------------------------------------------------|
| `MINTER_ROLE`     | Can mint ION tokens by transferring collateral and then minting ION            |
| `ADMIN_ROLE`      | Can set the contract params                                                    |
| `AMO_ROLE`        | Can mint ION tokens via protocol operations (only be granted to AMO contracts) |
| `PAUSER_ROLE`     | Can pause the contract                                                         |
| `UNPAUSER_ROLE`   | Can unpause the contract                                                       |
| `WITHDRAWER_ROLE` | Can withdraw ERC20 tokens from the contract                                    |

---

### PriceManager

- **Tracks real-time prices of staked stablecoins (sUSDe, sFRAX, sDAI)**.
- Uses **Muon Oracle & mainnet staking contracts** for **accurate price updates**.
- **Prevents AMO operations if price feed is unreliable**.
- **Allows emergency manual price updates via governance role**.

#### Security & Risk Management

- **Muon Oracle & Risk Management**
    - **Muon Oracles fetch real-time data from mainnet staking contracts** (sUSDe, sFRAX, sDAI).
    - **Fallback Manual Update Mechanism**:
        - If **Muon Oracle fails**, **governance can manually update price feeds**.
        - This prevents AMO from making **bad liquidity decisions** due to faulty price feeds.

##### Role-Based Access Control (RBAC)

| Role                 | Description                 |
|----------------------|-----------------------------|
| `TOKEN_UPDATER_ROLE` | Can update the asset states |
| `SETTER_ROLE`        | Can set the contract params |

---

## 💻 Running the Project

### Install Dependencies

```sh
npm install
```

### Run Tests

```sh
npx hardhat test
```

### Run Coverage

```sh
npx hardhat coverage
```

### Start Local Blockchain Node

```sh
npx hardhat node
```

### Run prettier script to prettify the codes

```sh
./prettify.sh
```
