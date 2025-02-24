// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPairFactory {
    function allPairsLength() external view returns (uint256);

    function isPair(address pair) external view returns (bool);

    function pairCodeHash() external view returns (bytes32);

    function getPair(address tokenA, address token, bool stable) external view returns (address);

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);

    function voter() external view returns (address);

    function allPairs(uint256) external view returns (address);

    function pairFee(address _pool) external view returns (uint256 fee);

    function getFee(bool) external view returns (uint256);

    function treasury() external view returns (address);

    function acceptFeeManager() external;

    function setPairFee(address _pair, uint256 _fee) external;

    function setFee(bool _stable, uint256 _fee) external;

    function feeSplit() external view returns (uint8);

    function getPoolFeeSplit(address _pool) external view returns (uint8 _poolFeeSplit);

    function setFeeSplit(uint8 _toFees, uint8 _toTreasury) external;

    function setPoolFeeSplit(address _pool, uint8 _toFees, uint8 _toTreasury) external;
}
