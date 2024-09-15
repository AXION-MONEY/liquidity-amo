// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./amo/ISolidlyV3LiquidityAMORoles.sol";
import "./amo/ISolidlyV3LiquidityAMOImmutables.sol";
import "./amo/ISolidlyV3LiquidityAMOVariables.sol";
import "./amo/ISolidlyV3LiquidityAMOViews.sol";
import "./amo/ISolidlyV3LiquidityAMOActions.sol";
import "./amo/ISolidlyV3LiquidityAMOEvents.sol";

interface ISolidlyV3LiquidityAMO is
    ISolidlyV3LiquidityAMORoles,
    ISolidlyV3LiquidityAMOImmutables,
    ISolidlyV3LiquidityAMOVariables,
    ISolidlyV3LiquidityAMOViews,
    ISolidlyV3LiquidityAMOActions,
    ISolidlyV3LiquidityAMOEvents
{}
