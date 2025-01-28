// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IMuonClient.sol";

contract MockMuonClient is IMuonClient {
    function verifyTSSAndGW(
        bytes memory _data,
        bytes calldata _reqId,
        SchnorrSign calldata _signature,
        bytes calldata _gatewaySignature
    ) public view {}
}
