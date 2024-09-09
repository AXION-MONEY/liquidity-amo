# Liquidity AMO —— rebalancing the liquidity and stable price altogether

## Organization
The AMO manages a significant portion of the USDC backing for the stablecoin (referred to as BOOST in this version). There are two branches:

- Main: For Solidly-v3 Dexes (based on Uniswap v3 contracts).
- Solidly-v2: For Solidly Dexes (based on Uniswap v2 contracts).

*Note 1:* These two branches have identical logic, they just interact with two different AMM contracts => similarity qualitatively over 90%
*Note 2:* Price rebalancing is triggered by a bot but can also be activated by the community through the publicAMO.sol contract. This rebalancing is designed to be beneficial for the protocol, with no risk to the stablecoin from community actions or flash loans.

## Audit Scope
- Both AMO branches.
- The utils contract (which manages veNFT, our voting power in Dexes).

*Note*: Each Solidly Dex has slightly different contract versions, meaning adaptations for each chain or Dex may be required. This could lead to later ad-hoc reviews by an auditor.

## Running the project
This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a script that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.ts
```
