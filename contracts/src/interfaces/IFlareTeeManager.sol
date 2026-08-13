// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice Minimal live FlareTeeManager surface used by Continuity.
interface IFlareTeeManager {
    struct PublicKey {
        bytes32 x;
        bytes32 y;
    }

    struct TeeMachineWithAttestationData {
        address teeId;
        address initialTeeId;
        string url;
        bytes32 codeHash;
        bytes32 platform;
    }

    struct TeeInstructionParams {
        bytes32 opType;
        bytes32 opCommand;
        bytes message;
        address[] cosigners;
        uint64 cosignersThreshold;
        address claimBackAddress;
    }

    function sendInstructions(address[] calldata teeIds, TeeInstructionParams calldata instructionParams)
        external
        payable
        returns (bytes32 instructionId);

    function getExtensionId(address teeId) external view returns (uint256);

    function getTeeMachineStatus(address teeId) external view returns (uint8);

    function getPublicKey(address teeId) external view returns (PublicKey memory publicKey);

    function getTeeMachineWithAttestationData(address teeId)
        external
        view
        returns (TeeMachineWithAttestationData memory machine);

    function getTeeExtensionInstructionsSender(uint256 extensionId) external view returns (address);

    function getTeeExtensionStateVerifier(uint256 extensionId) external view returns (address);

    function isCodeHashPlatformSupported(uint256 extensionId, bytes32 codeHash, bytes32 platform)
        external
        view
        returns (bool supported);
}
