// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/**
 * @title IVeloVoter Interface
 * @notice This interface defines the functions, events, and errors for the VeloVoter contract.
 */
interface IVeloVoter {
    // Errors

    /**
     * @notice Thrown when the user has already voted or deposited.
     */
    error AlreadyVotedOrDeposited();

    /**
     * @notice Thrown when the distribution window condition is not met.
     */
    error DistributeWindow();

    /**
     * @notice Thrown when the factory path is not approved.
     */
    error FactoryPathNotApproved();

    /**
     * @notice Thrown when the gauge is already killed.
     */
    error GaugeAlreadyKilled();

    /**
     * @notice Thrown when the gauge is already revived.
     */
    error GaugeAlreadyRevived();

    /**
     * @notice Thrown when the gauge already exists.
     */
    error GaugeExists();

    /**
     * @notice Thrown when the gauge does not exist for the specified pool.
     * @param _pool The address of the pool.
     */
    error GaugeDoesNotExist(address _pool);

    /**
     * @notice Thrown when the gauge is not alive.
     * @param _gauge The address of the gauge.
     */
    error GaugeNotAlive(address _gauge);

    /**
     * @notice Thrown when the managed NFT is inactive.
     */
    error InactiveManagedNFT();

    /**
     * @notice Thrown when the maximum voting number is set too low.
     */
    error MaximumVotingNumberTooLow();

    /**
     * @notice Thrown when non-zero votes exist when zero was expected.
     */
    error NonZeroVotes();

    /**
     * @notice Thrown when the provided address is not a valid pool.
     */
    error NotAPool();

    /**
     * @notice Thrown when the caller is neither approved nor the owner.
     */
    error NotApprovedOrOwner();

    /**
     * @notice Thrown when the caller is not the governor.
     */
    error NotGovernor();

    /**
     * @notice Thrown when the caller is not the emergency council.
     */
    error NotEmergencyCouncil();

    /**
     * @notice Thrown when the caller is not the minter.
     */
    error NotMinter();

    /**
     * @notice Thrown when the NFT is not whitelisted.
     */
    error NotWhitelistedNFT();

    /**
     * @notice Thrown when the token is not whitelisted.
     */
    error NotWhitelistedToken();

    /**
     * @notice Thrown when the provided value is the same as the existing value.
     */
    error SameValue();

    /**
     * @notice Thrown when an operation is attempted during a special voting window.
     */
    error SpecialVotingWindow();

    /**
     * @notice Thrown when too many pools are provided.
     */
    error TooManyPools();

    /**
     * @notice Thrown when array lengths are not equal.
     */
    error UnequalLengths();

    /**
     * @notice Thrown when a balance is zero when a non-zero value is expected.
     */
    error ZeroBalance();

    /**
     * @notice Thrown when a zero address is provided.
     */
    error ZeroAddress();

    // Events

    /**
     * @notice Emitted when a new gauge is created.
     * @param poolFactory The address of the pool factory.
     * @param votingRewardsFactory The address of the voting rewards factory.
     * @param gaugeFactory The address of the gauge factory.
     * @param pool The address of the pool.
     * @param bribeVotingReward The address for bribe voting rewards.
     * @param feeVotingReward The address for fee voting rewards.
     * @param gauge The address of the gauge.
     * @param creator The address of the creator.
     */
    event GaugeCreated(
        address indexed poolFactory,
        address indexed votingRewardsFactory,
        address indexed gaugeFactory,
        address pool,
        address bribeVotingReward,
        address feeVotingReward,
        address gauge,
        address creator
    );

    /**
     * @notice Emitted when a gauge is killed.
     * @param gauge The address of the gauge that was killed.
     */
    event GaugeKilled(address indexed gauge);

    /**
     * @notice Emitted when a gauge is revived.
     * @param gauge The address of the gauge that was revived.
     */
    event GaugeRevived(address indexed gauge);

    /**
     * @notice Emitted when a vote is cast.
     * @param voter The address of the voter.
     * @param pool The address of the pool voted for.
     * @param tokenId The ID of the veNFT used for voting.
     * @param weight The weight of the vote.
     * @param totalWeight The total weight after voting.
     * @param timestamp The timestamp when the vote was cast.
     */
    event Voted(
        address indexed voter,
        address indexed pool,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a vote is abstained.
     * @param voter The address of the voter.
     * @param pool The address of the pool for which the abstention occurred.
     * @param tokenId The ID of the veNFT used.
     * @param weight The weight that was abstained.
     * @param totalWeight The total weight after abstention.
     * @param timestamp The timestamp when the abstention occurred.
     */
    event Abstained(
        address indexed voter,
        address indexed pool,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a reward notification is sent.
     * @param sender The address notifying the reward.
     * @param reward The reward token address.
     * @param amount The amount of reward.
     */
    event NotifyReward(address indexed sender, address indexed reward, uint256 amount);

    /**
     * @notice Emitted when a reward is distributed.
     * @param sender The address distributing the reward.
     * @param gauge The gauge receiving the reward.
     * @param amount The amount of reward distributed.
     */
    event DistributeReward(address indexed sender, address indexed gauge, uint256 amount);

    /**
     * @notice Emitted when a token is whitelisted or unwhitelisted.
     * @param whitelister The address performing the whitelisting.
     * @param token The token address.
     * @param _bool The whitelisting status (true for whitelisted, false for unwhitelisted).
     */
    event WhitelistToken(address indexed whitelister, address indexed token, bool indexed _bool);

    /**
     * @notice Emitted when an NFT is whitelisted or unwhitelisted.
     * @param whitelister The address performing the whitelisting.
     * @param tokenId The ID of the NFT.
     * @param _bool The whitelisting status (true for whitelisted, false for unwhitelisted).
     */
    event WhitelistNFT(address indexed whitelister, uint256 indexed tokenId, bool indexed _bool);

    // View Functions

    /**
     * @notice Returns the trusted forwarder address used by factories.
     * @return The forwarder address.
     */
    function forwarder() external view returns (address);

    /**
     * @notice Returns the address of the ve token that governs these contracts.
     * @return The address of the ve token.
     */
    function ve() external view returns (address);

    /**
     * @notice Returns the factory registry address for valid pool, gauge, and rewards factories.
     * @return The factory registry address.
     */
    function factoryRegistry() external view returns (address);

    /**
     * @notice Returns the address of the Minter contract.
     * @return The minter address.
     */
    function minter() external view returns (address);

    /**
     * @notice Returns the address of the governor.
     * @return The governor address.
     */
    function governor() external view returns (address);

    /**
     * @notice Returns the address of the epoch-based governor.
     * @return The epoch governor address.
     */
    function epochGovernor() external view returns (address);

    /**
     * @notice Returns the address of the emergency council.
     * @return The emergency council address.
     */
    function emergencyCouncil() external view returns (address);

    /**
     * @notice Returns the total voting weight.
     * @return The total weight.
     */
    function totalWeight() external view returns (uint256);

    /**
     * @notice Returns the maximum number of pools a voter can vote for.
     * @return The maximum voting number.
     */
    function maxVotingNum() external view returns (uint256);

    /**
     * @notice Returns the gauge associated with a given pool.
     * @param pool The pool address.
     * @return The gauge address.
     */
    function gauges(address pool) external view returns (address);

    /**
     * @notice Returns the pool associated with a given gauge.
     * @param gauge The gauge address.
     * @return The pool address.
     */
    function poolForGauge(address gauge) external view returns (address);

    /**
     * @notice Returns the fee voting reward address associated with a gauge.
     * @param gauge The gauge address.
     * @return The fee voting reward address.
     */
    function gaugeToFees(address gauge) external view returns (address);

    /**
     * @notice Returns the bribe voting reward address associated with a gauge.
     * @param gauge The gauge address.
     * @return The bribe voting reward address.
     */
    function gaugeToBribe(address gauge) external view returns (address);

    /**
     * @notice Returns the voting weight for a specific pool.
     * @param pool The pool address.
     * @return The weight of the pool.
     */
    function weights(address pool) external view returns (uint256);

    /**
     * @notice Returns the vote weight for a given veNFT and pool.
     * @param tokenId The ID of the veNFT.
     * @param pool The pool address.
     * @return The vote weight.
     */
    function votes(uint256 tokenId, address pool) external view returns (uint256);

    /**
     * @notice Returns the total used voting weight for a given veNFT.
     * @param tokenId The ID of the veNFT.
     * @return The used weight.
     */
    function usedWeights(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Returns the timestamp of the last vote for a given veNFT.
     * @param tokenId The ID of the veNFT.
     * @return The timestamp of the last vote.
     */
    function lastVoted(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Checks if an address is a valid gauge.
     * @param _gauge The address to check.
     * @return True if the address is a gauge, false otherwise.
     */
    function isGauge(address _gauge) external view returns (bool);

    /**
     * @notice Checks if a token is whitelisted for voting rewards.
     * @param token The token address.
     * @return True if whitelisted, false otherwise.
     */
    function isWhitelistedToken(address token) external view returns (bool);

    /**
     * @notice Checks if an NFT is whitelisted for special voting.
     * @param tokenId The NFT ID.
     * @return True if whitelisted, false otherwise.
     */
    function isWhitelistedNFT(uint256 tokenId) external view returns (bool);

    /**
     * @notice Checks if a gauge is alive.
     * @param gauge The gauge address.
     * @return True if the gauge is alive, false otherwise.
     */
    function isAlive(address gauge) external view returns (bool);

    /**
     * @notice Returns the claimable reward amount for a gauge.
     * @param gauge The gauge address.
     * @return The claimable amount.
     */
    function claimable(address gauge) external view returns (uint256);

    /**
     * @notice Returns the number of pools that have an associated gauge.
     * @return The number of pools.
     */
    function length() external view returns (uint256);

    // State-changing Functions

    /**
     * @notice Notifies the contract of a reward amount to distribute to gauges.
     * @dev Called by the Minter to distribute weekly emissions rewards.
     *      Assumes that totalWeight is non-zero.
     * @param _amount The amount of rewards to distribute.
     */
    function notifyRewardAmount(uint256 _amount) external;

    /**
     * @notice Distributes rewards to gauges within a specified index range.
     * @param _start The starting index of gauges.
     * @param _finish The ending index of gauges.
     */
    function distribute(uint256 _start, uint256 _finish) external;

    /**
     * @notice Distributes rewards to a specified list of gauges.
     * @param _gauges An array of gauge addresses.
     */
    function distribute(address[] memory _gauges) external;

    /**
     * @notice Updates the voting rewards for a given veNFT.
     * @param _tokenId The ID of the veNFT.
     */
    function poke(uint256 _tokenId) external;

    /**
     * @notice Casts votes for pools using a veNFT.
     * @dev Votes are distributed proportionally based on the provided weights.
     *      Can only vote or deposit into a managed NFT once per epoch.
     *      Reverts if the lengths of _poolVote and _weights do not match.
     * @param _tokenId The ID of the veNFT used for voting.
     * @param _poolVote An array of pool addresses to vote for.
     * @param _weights An array of weights corresponding to each pool.
     */
    function vote(uint256 _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external;

    /**
     * @notice Resets the voting state for a veNFT.
     * @dev Must be called to modify veNFT state (e.g., merge, split, deposit).
     *      Cannot reset in the same epoch in which a vote was cast.
     * @param _tokenId The ID of the veNFT to reset.
     */
    function reset(uint256 _tokenId) external;

    /**
     * @notice Deposits into a managed veNFT.
     * @dev Can only vote or deposit into a managed NFT once per epoch.
     *      NFTs deposited into a managed NFT will be re-locked to the maximum lock time on withdrawal.
     *      Reverts if not approved, if the managed NFT is inactive, or if within the privileged window.
     * @param _tokenId The ID of the veNFT performing the deposit.
     * @param _mTokenId The ID of the managed veNFT.
     */
    function depositManaged(uint256 _tokenId, uint256 _mTokenId) external;

    /**
     * @notice Withdraws from a managed veNFT.
     * @dev Cannot withdraw in the same epoch as the deposit.
     *      The withdrawn NFT will be re-locked to the maximum lock time.
     * @param _tokenId The ID of the veNFT to withdraw from.
     */
    function withdrawManaged(uint256 _tokenId) external;

    /**
     * @notice Claims emissions rewards from specified gauges.
     * @param _gauges An array of gauge addresses from which to claim rewards.
     */
    function claimRewards(address[] memory _gauges) external;

    /**
     * @notice Claims bribe rewards for a given veNFT.
     * @dev Utility function to batch bribe claims.
     * @param _bribes An array of bribe voting reward contract addresses.
     * @param _tokens A two-dimensional array of token addresses used as bribes.
     * @param _tokenId The ID of the veNFT for which to claim bribes.
     */
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external;

    /**
     * @notice Claims fee rewards for a given veNFT.
     * @dev Utility function to batch fee claims.
     * @param _fees An array of fee voting reward contract addresses.
     * @param _tokens A two-dimensional array of token addresses used as fees.
     * @param _tokenId The ID of the veNFT for which to claim fees.
     */
    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external;

    /**
     * @notice Sets a new governor.
     * @dev Reverts if called by anyone other than the current governor.
     * @param _governor The address of the new governor.
     */
    function setGovernor(address _governor) external;

    /**
     * @notice Sets a new epoch-based governor.
     * @dev Reverts if called by anyone other than the current governor.
     * @param _epochGovernor The address of the new epoch governor.
     */
    function setEpochGovernor(address _epochGovernor) external;

    /**
     * @notice Sets a new emergency council.
     * @dev Reverts if called by anyone other than the current emergency council.
     * @param _emergencyCouncil The address of the new emergency council.
     */
    function setEmergencyCouncil(address _emergencyCouncil) external;

    /**
     * @notice Sets the maximum number of gauges a voter can vote for.
     * @dev Reverts if called by a non-governor, if the number is too low, or if the value remains unchanged.
     * @param _maxVotingNum The new maximum voting number.
     */
    function setMaxVotingNum(uint256 _maxVotingNum) external;

    /**
     * @notice Whitelists or unwhitelists a token for use in bribes.
     * @dev Reverts if called by a non-governor.
     * @param _token The token address.
     * @param _bool The whitelisting status (true for whitelisted, false for unwhitelisted).
     */
    function whitelistToken(address _token, bool _bool) external;

    /**
     * @notice Whitelists or unwhitelists an NFT for voting within the privileged window.
     * @dev Reverts if called by a non-governor or if already whitelisted.
     * @param _tokenId The ID of the NFT.
     * @param _bool The whitelisting status (true for whitelisted, false for unwhitelisted).
     */
    function whitelistNFT(uint256 _tokenId, bool _bool) external;

    /**
     * @notice Creates a new gauge for a given pool.
     * @dev Unpermissioned creation; the governor can create a gauge for any pool.
     * @param _poolFactory The address of the pool factory.
     * @param _pool The address of the pool.
     * @return The address of the newly created gauge.
     */
    function createGauge(address _poolFactory, address _pool) external returns (address);

    /**
     * @notice Kills a gauge, preventing new emissions and deposits.
     * @dev Reverts if called by a non-emergency council or if the gauge is already killed.
     * @param _gauge The address of the gauge to kill.
     */
    function killGauge(address _gauge) external;

    /**
     * @notice Revives a killed gauge, allowing new emissions and deposits.
     * @dev Reverts if called by a non-emergency council or if the gauge is not killed.
     * @param _gauge The address of the gauge to revive.
     */
    function reviveGauge(address _gauge) external;

    /**
     * @notice Updates emissions claims for an array of gauges.
     * @param _gauges An array of gauge addresses to update.
     */
    function updateFor(address[] memory _gauges) external;

    /**
     * @notice Updates emissions claims for gauges in a specified range of pool indices.
     * @param _start The starting index of pools.
     * @param _end The ending index of pools.
     */
    function updateFor(uint256 _start, uint256 _end) external;

    /**
     * @notice Updates emissions claims for a single gauge.
     * @param _gauge The address of the gauge to update.
     */
    function updateFor(address _gauge) external;
}
