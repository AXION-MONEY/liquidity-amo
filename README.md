# Liquidity AMO —— rebalancing the liquidity and stable price altogether

## Organization
The AMO manages a significant portion of the USDC backing for the stablecoin (referred to as BOOST in this version). There are two branches:

- Main: For Solidly-v2 Dexes (based on Uniswap v2 contracts).
- Solidly-v3: For Solidly Dexes (based on Uniswap v3 contracts).

Note: Price rebalancing is triggered by a bot but can also be activated by the community through the publicAMO.sol contract. This rebalancing is designed to be beneficial for the protocol, with no risk to the stablecoin from community actions or flash loans.

## Audit Scope
- Both AMO branches.
- The utils contract (which manages veNFT, our voting power in Dexes).

Note: Each Solidly Dex has slightly different contract versions, meaning adaptations for each chain or Dex may be required. This could lead to later ad-hoc reviews by an auditor.

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
