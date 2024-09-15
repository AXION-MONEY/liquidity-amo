// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title SolidlyV3LiquidityAMO AccessControl roles
/// @notice
interface ISolidlyV3LiquidityAMORoles {
    function SETTER_ROLE() external view returns (bytes32);

    function AMO_ROLE() external view returns (bytes32);

    function OPERATOR_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function UNPAUSER_ROLE() external view returns (bytes32);
}
