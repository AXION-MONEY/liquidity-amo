// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "./interfaces/IMuonClient.sol";
import "./SchnorrSECP256K1Verifier.sol";

contract MuonClient is IMuonClient, SchnorrSECP256K1Verifier, AccessControlEnumerable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    address public validGateway;
    uint256 public appId;
    PublicKey public pubKey;
    bool public checkGatewaySignature;

    event ValidGatewayUpdated(address newValidGateway);
    event AppIdUpdated(uint256 newAppId);
    event PubKeyUpdated(uint256 x, uint8 parity);
    event CheckGatewaySignatureUpdated(bool newValue);

    error InvalidSignature();
    error InvalidGatewaySignature();

    constructor(address _validGateway, uint256 _appId, PublicKey memory _publicKey, bool _checkGatewaySignature) {
        validatePubKey(_publicKey.x);

        validGateway = _validGateway;
        appId = _appId;
        pubKey = _publicKey;
        checkGatewaySignature = _checkGatewaySignature;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SETTER_ROLE, msg.sender);
    }

    /// @notice Verifies a Muon signature of the given data
    /// @param _data data being signed
    /// @param _reqId request id that the signature was obtained from
    /// @param _signature signature of the data
    /// @param _gatewaySignature signature of the data by the gateway (specific Muon node)
    /// reverts if the signature is invalid
    function verifyTSSAndGW(
        bytes memory _data,
        bytes calldata _reqId,
        SchnorrSign calldata _signature,
        bytes calldata _gatewaySignature
    ) public view {
        bytes32 _hash = keccak256(abi.encodePacked(appId, _reqId, _data));
        if (!verifySignature(pubKey.x, pubKey.parity, _signature.signature, uint256(_hash), _signature.nonce))
            revert InvalidSignature();
        if (checkGatewaySignature) {
            _hash = _hash.toEthSignedMessageHash();
            address gatewaySignatureSigner = _hash.recover(_gatewaySignature);

            if (gatewaySignatureSigner != validGateway) revert InvalidGatewaySignature();
        }
    }

    /// @notice Updates the validGateway address
    /// @param _validGateway The new valid gateway address
    /// @dev Only accounts with SETTER_ROLE can call this function
    function setValidGateway(address _validGateway) public onlyRole(SETTER_ROLE) {
        validGateway = _validGateway;
        emit ValidGatewayUpdated(_validGateway);
    }

    /// @notice Updates the appId
    /// @param _appId The new appId
    /// @dev Only accounts with SETTER_ROLE can call this function
    function setAppId(uint256 _appId) public onlyRole(SETTER_ROLE) {
        appId = _appId;
        emit AppIdUpdated(_appId);
    }

    /// @notice Updates the public key
    /// @param _publicKey The new public key
    /// @dev Only accounts with SETTER_ROLE can call this function
    function setPubKey(PublicKey memory _publicKey) public onlyRole(SETTER_ROLE) {
        validatePubKey(_publicKey.x);
        pubKey = _publicKey;
        emit PubKeyUpdated(_publicKey.x, _publicKey.parity);
    }

    /// @notice Updates the checkGatewaySignature flag
    /// @param _checkGatewaySignature The new value for the flag
    /// @dev Only accounts with SETTER_ROLE can call this function
    function setCheckGatewaySignature(bool _checkGatewaySignature) public onlyRole(SETTER_ROLE) {
        checkGatewaySignature = _checkGatewaySignature;
        emit CheckGatewaySignatureUpdated(_checkGatewaySignature);
    }
}
