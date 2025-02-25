// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IPoolFactory {
    /**
     * @notice Emitted when the fee manager is set.
     */
    event SetFeeManager(address feeManager);
    /**
     * @notice Emitted when the pauser is set.
     */
    event SetPauser(address pauser);
    /**
     * @notice Emitted when the pause state is updated.
     */
    event SetPauseState(bool state);
    /**
     * @notice Emitted when the voter is set.
     */
    event SetVoter(address voter);
    /**
     * @notice Emitted when a pool is created.
     * @param token0 The first token of the pool.
     * @param token1 The second token of the pool.
     * @param stable Indicates whether the pool is stable.
     * @param pool The address of the created pool.
     * @param (unnamed) A numeric parameter.
     */
    event PoolCreated(address indexed token0, address indexed token1, bool indexed stable, address pool, uint256);
    /**
     * @notice Emitted when a custom fee is set for a pool.
     * @param pool The pool address.
     * @param fee The custom fee.
     */
    event SetCustomFee(address indexed pool, uint256 fee);

    /**
     * @notice Thrown when the fee is invalid.
     */
    error FeeInvalid();
    /**
     * @notice Thrown when the fee is too high.
     */
    error FeeTooHigh();
    /**
     * @notice Thrown when the pool is invalid.
     */
    error InvalidPool();
    /**
     * @notice Thrown when the caller is not the fee manager.
     */
    error NotFeeManager();
    /**
     * @notice Thrown when the caller is not the pauser.
     */
    error NotPauser();
    /**
     * @notice Thrown when the caller is not the voter.
     */
    error NotVoter();
    /**
     * @notice Thrown when the pool already exists.
     */
    error PoolAlreadyExists();
    /**
     * @notice Thrown when two addresses are the same.
     */
    error SameAddress();
    /**
     * @notice Thrown when the fee is zero.
     */
    error ZeroFee();
    /**
     * @notice Thrown when an address provided is zero.
     */
    error ZeroAddress();

    /**
     * @notice Returns the number of pools created from this factory.
     */
    function allPoolsLength() external view returns (uint256);

    /**
     * @notice Returns whether a given address is a valid pool created by this factory.
     * @param pool The pool address to check.
     */
    function isPool(address pool) external view returns (bool);

    /**
     * @notice Returns the address of a pool created by this factory.
     * @param tokenA A token address.
     * @param tokenB The other token address.
     * @param stable True if the pool is stable, false if volatile.
     */
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);

    /**
     * @dev Only called once to set the voter. Once set, the value is immutable.
     * @param _voter The voter address.
     */
    function setVoter(address _voter) external;

    function setPauser(address _pauser) external;

    function setPauseState(bool _state) external;

    function setFeeManager(address _feeManager) external;

    /**
     * @notice Sets the default fee for stable and volatile pools.
     * @dev Throws if the fee is higher than the maximum or is zero.
     * @param _stable True for stable pools, false for volatile.
     * @param _fee The fee value.
     */
    function setFee(bool _stable, uint256 _fee) external;

    /**
     * @notice Sets an overriding fee for a specific pool.
     * @dev A custom fee of zero means the default fee will be used.
     */
    function setCustomFee(address _pool, uint256 _fee) external;

    /**
     * @notice Returns the fee for a pool (custom fees are possible).
     */
    function getFee(address _pool, bool _stable) external view returns (uint256);

    /**
     * @notice Creates a pool given two tokens and their stable/volatile flag.
     * @dev Token order does not matter.
     * @param tokenA A token address.
     * @param tokenB The other token address.
     * @param stable True if the pool is stable, false if volatile.
     */
    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);

    function isPaused() external view returns (bool);

    function voter() external view returns (address);

    function implementation() external view returns (address);
}
