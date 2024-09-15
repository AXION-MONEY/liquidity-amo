// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMinter {
    // State Variables
    function boostAddress() external view returns (address);

    function collateralAddress() external view returns (address);

    function treasury() external view returns (address);

    // Events
    event TokensAddressesUpdated(address indexed boostAddress, address indexed collateralAddress);
    event CollateralRatioUpdated(uint256 newRatio);
    event TreasuryUpdated(address newTreasury);
    event TokenMinted(address indexed user, address indexed to, uint256 amount);
    event TokenProtocolMinted(address indexed user, address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed tokenAddress, uint256 amount);

    // Function Signatures
    function pause() external;

    function unpause() external;

    function setTokens(address _boost, address _collateral) external;

    function setTreasury(address _treasury) external;

    function mint(address _to, uint256 _amount) external;

    function protocolMint(address _to, uint256 _amount) external;

    function withdrawToken(address _token, uint256 _amount) external;
}
