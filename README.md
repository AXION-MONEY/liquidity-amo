# Liquidity AMO: Automated Market Operations for ION Stability & Liquidity Management

## Overview of principles

1) High-level view: ION is a fit-for-Defi stablecoin. Its collateral is always available on pools, which guarantees its
   redeem-ability, while being profitable. The liquidity and peg are both managed by the LiquidityAMO smart contract
   which
   has a simple logic:
    * When ION is above par, it mints ION tokens, selling them for USD, then farming the USDC with free-minted BOOST
    * When ION is below par, it removes liquidity from the pool (both ION and USD), and buys back ION from the pool with
      the
      USD
2) There are a few complexities under the hood:
    * When a user buys ION with USD, the Axion protocol (via the LiquidityAMO contract) mints ION for the user and sells
      them for USD. Then it pairs the USD it receives with "Free-minted ION" (called protocol-owned ION) in the Frax
      vocabulary and farms it. This free-minted ION is burned when liquidity is removed from the pool (the free-minted
      ION only serves to farm the USD backing)
    * USD is a generic name for a reference stable coin paired with ION in the AMO. ION can be paired with USDC and USDT
      which have value 1, or with staked stablecoins (such as sDAI or sUSDe which fundamental value very progressively
      increase in time)
    * ION can be paired with multiple reference stablecoins on the same chain (each with its own pool), offering a lot
      of
      trading/arbitrage opportunities

## Technical overview

The **Liquidity AMO (Automated Market Operations)** ensures **ION price stability and redeem-ability/liquidity**:

* It **mints, sells, adds liquidity, removes liquidity, and burns ION** based on supply and demand ( pool balances in
  uni-v2 "fully-range" pool types, or on the deviation between implied and fundamental prices in CL pools), all based on
  **real-time market conditions**.
* It can dynamically interact with **multiple AMMs (Automated Market Makers) and stablecoins**.

The AMO operates **permissionlessly**, meaning that **anyone** can trigger `mintSellFarm` & `unfarmBuyBurn` to
**rebalance ION’s price**. The system **cannot be manipulated** by flash loans or external actors, ensuring secure and
optimal liquidity management.

The **AMO** supports both **stablecoins** and **Staked Stable Coins (sUSDe, sDAI, ...)** pools. For staked stablecoin
pairs, the AMO executes Automated Market Operations based on data from the price manager contract. This price can be
updated permissionlessly using the **Muon Network**, which retrieves price data from their corresponding contract on the
Mainnet and generates a signature with the necessary data.

---

## Supported DEXes

LiquidityAMO interacts with **both Concentrated Liquidity AMMs (CLAMM) and Traditional AMMs (Uniswap V2-style pools)**
Any DEX that uses same pool logic (codebase) can easily be added and integrated:

### CLAMM (Concentrated Liquidity)

- **Aerodrome CL** and **Velodrome CL**
- **Algebra V1.0, V1.9 and Integral**
- **Uniswap V3**
- **Solidly V3 (CL)**
- **Ramses CL**

### Uniswap V2-Style AMMs

- **Aerodrome and Velodrome**
- **Thena and Equalizer**
- **Solidly V2**

There are fewer variations in Uniswap v2 pools across Dexes, so we expect a larger compatibility.

---

## Supported Pair Tokens

The AMO primarily interacts with **stablecoins & staked stable assets** to manage ION’s liquidity:

### Supported Stablecoins

- **USDC** (Circle)
- **USDT** (Tether)
- **DAI** (MakerDAO)
- **FRAX** (Frax Finance)
- **Any Non-Exotic Stable Coin**

### Supported Staked Stablecoins

- **sUSDe** (Ethena Staked USDe)
- **sFRAX** (Frax Staked FRAX)
- **sDAI** (MakerDAO Staked DAI)
- Adding staked stable coins essentially requires building a dedicated oracle

---

## Core Components

### ION Stable Coin Contract

The ION contract implements an ERC-20 token called "ION," which serves as the foundation of the ION stablecoin project.

#### Key Contract Functions

| Function                | Description                                                                                |
|-------------------------|--------------------------------------------------------------------------------------------|
| `pause()` & `unpause()` | Function can be delegated to a security monitoring firms for automatic responses.          |
| `protocolMint()`        | Mint new tokens (using the Minter.Sol contract) and send them to a specified address (to_) |

#### Security & Risk Management

##### Role-Based Access Control (RBAC) for the ION stablecoin contract

| Role                 | Description                                             | Operator's type                                  |
|----------------------|---------------------------------------------------------|--------------------------------------------------|
| `MINTER_ROLE`        | LiquidityAMO contract mints through the minter contract | Minter contract                                  |
| `PAUSER_ROLE`        | Can pause the contract                                  | Delegated to security monitoring services (EOAs) |
| `UNPAUSER_ROLE`      | Can unpause the contract                                | Msig                                             |
| `DEFAULT_ADMIN_ROLE` | Can manage roles                                        | Msig                                             |

#### Use ProxyAdmin for upgrading the contract

The owner of the ProxyAdmin is the protocol's msig under a timelock

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

      $$
      \text{ionAmountWithoutFee} = \sqrt{\frac{\text{pairTokenReserve} \times \text{ionReserve}}{\text{ionTargetPrice}}} - \text{ionReserve}
      $$

      An additional fee adjustment is added:

      $$
      \text{ionAmount} = \frac{\text{ionAmountWithoutFee}}{1 - \text{poolFee}}
      $$

- **Unfarm-Buy-Burn Calculation**

  When ION is below the target price, V2AMO initiates the unfarm–buy–burn process by withdrawing a calculated amount of
  liquidity from the gauge, removing liquidity from the pool, and then swapping to buy ION (which is subsequently
  burned). The key step is determining how much liquidity to unfarm. This is computed using the following formulas:

- **Calculate the Square Root Ratio:**

  The square root ratio adjusts the reserves based on the target price:

$$
\text{sqrtResRatio} = \sqrt{\frac{\text{pairTokenReserve}}{\text{ionReserve} \times \text{ionTargetPrice}}}
$$

- **Compute the Removal Percentage:**

  This percentage determines the fraction of total liquidity that should be withdrawn, factoring in the pool fee:

$$
\text{removalPercentage} = \frac{1 - \text{sqrtResRatio}}{1 - (\text{poolFee} \times \text{sqrtResRatio})}
$$

- **Determine the Liquidity to Unfarm:**

  Finally, the liquidity amount is calculated as a proportion of the total LP token supply:

$$
\text{liquidity} = \text{totalLp} \times \text{removalPercentage}
$$

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

##### Role-Based Access Control (RBAC) for the LiquidityAMO contract

| Role                    | Description                                                                      | Operator's type                           |
|-------------------------|----------------------------------------------------------------------------------|-------------------------------------------|
| `SETTER_ROLE`           | Can set the contract params & Can add/remove users for bypassing the swap ratio  | Msig                                      |
| `PAUSER_ROLE`           | Can pause the contract                                                           | Delegated to security monitoring services |
| `UNPAUSER_ROLE`         | Can unpause the contract                                                         | Msig                                      |
| `WITHDRAWER_ROLE`       | Can withdraw ERC20 tokens from the contract & Can remove liquidity from the pool | Msig                                      |
| `REWARD_COLLECTOR_ROLE` | Can collect rewards from the gauge (only for V2AMO)                              | Msig                                      |
| `DEFAULT_ADMIN_ROLE`    | Can manage roles                                                                 | Msig                                      |

##### Use ProxyAdmin for upgrading the contract

The owner of the ProxyAdmin is the protocol's msig under a timelock

------

### Minter

#### Security & Risk Management

- **Manages ION minting & burning**.
- **Security measures**:
    - **Only callable by authorized AMO contracts**.
    - **Protocol-owned minting only for liquidity rebalancing**.
    - **Timelock governance for emergency pauses**.

##### Role-Based Access Control (RBAC) for the Minter contract

| Role                 | Description                                                                                                    | Operator's type                                    |
|----------------------|----------------------------------------------------------------------------------------------------------------|----------------------------------------------------|
| `MINTER_ROLE`        | Can mint ION tokens by transferring collateral and then minting ION                                            | (Potentially vault contracts for a future upgrade) |
| `ADMIN_ROLE`         | Can set the contract params                                                                                    | Msig                                               |
| `AMO_ROLE`           | Can mint ION tokens via protocol operations                                                                    | LiquidityAMO contract                              |
| `PAUSER_ROLE`        | Can pause the contract                                                                                         | Delegated to security monitoring services          |
| `UNPAUSER_ROLE`      | Can unpause the contract                                                                                       | Msig                                               |
| `WITHDRAWER_ROLE`    | Standard role to potentially withdraw ERC20 tokens from a contract to the msig (not in use in current version) | Msig                                               |
| `DEFAULT_ADMIN_ROLE` | Can manage roles                                                                                               | Msig                                               |

##### Use ProxyAdmin for upgrading the contract

The owner of the ProxyAdmin is the protocol's msig under a timelock

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

##### Role-Based Access Control (RBAC) for the PriceManager contract

| Role                 | Description                 | Operator's type |
|----------------------|-----------------------------|-----------------|
| `TOKEN_UPDATER_ROLE` | Can update the asset states | Msig            |
| `SETTER_ROLE`        | Can set the contract params | Msig            |
| `DEFAULT_ADMIN_ROLE` | Can manage roles            | Msig            |

##### Use ProxyAdmin for upgrading the contract

The owner of the ProxyAdmin is the protocol's msig under a timelock

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
