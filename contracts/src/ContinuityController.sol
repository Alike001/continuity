// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IFlareTeeManager } from "./interfaces/IFlareTeeManager.sol";

/// @title ContinuityController
/// @notice Verifies FCC extension state and enforces one rollback-safe snapshot lineage.
contract ContinuityController {
    // Each literal is shorter than 32 bytes and intentionally right-padded with zeros.
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant STATE_VERSION = bytes32("CONTINUITY_STATE_V1");
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant OP_TYPE = bytes32("CONTINUITY");
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant OP_SNAPSHOT = bytes32("SNAPSHOT");
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant OP_RESTORE = bytes32("RESTORE");

    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 private constant TEE_ACTION_RESULT_PREFIX = bytes32("TEE_ACTION_RESULT");
    uint8 private constant TEE_STATUS_INITIALIZED = 1;
    uint8 private constant TEE_STATUS_PRODUCTION = 2;
    uint8 private constant TEE_STATUS_PAUSED = 4;
    uint8 private constant ACTION_ERROR = 0;
    uint8 private constant ACTION_SUCCESS = 1;
    uint256 private constant SECP256K1_HALF_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    struct ExpectedState {
        uint64 epoch;
        bytes32 root;
        bool exists;
    }

    struct PendingSnapshot {
        address sourceTee;
        address recoveryTee;
        uint64 nonce;
        uint64 epoch;
        bytes32 parentRoot;
        bool exists;
    }

    struct PendingRecovery {
        address recoveryTee;
        uint64 epoch;
        bytes32 stateRoot;
        bytes32 ciphertextDigest;
        bool exists;
    }

    struct SnapshotResult {
        bytes32 applicationId;
        address sourceTee;
        address recoveryTee;
        uint64 nonce;
        uint64 epoch;
        bytes32 parentRoot;
        bytes32 stateRoot;
        bytes ciphertext;
    }

    struct RecoveryResult {
        bytes32 applicationId;
        address recoveryTee;
        uint64 epoch;
        bytes32 stateRoot;
        bytes32 ciphertextDigest;
    }

    error NotOwner();
    error ZeroAddress();
    error ExtensionAlreadyConfigured();
    error ExtensionNotConfigured();
    error InvalidInstructionsSender();
    error InvalidStateVerifier();
    error InvalidMachinePair();
    error WrongExtension(address teeId);
    error WrongMachineStatus(address teeId, uint8 expected, uint8 actual);
    error UnsupportedMachineVersion(address teeId);
    error MachinesNotConfigured();
    error SnapshotInFlight(bytes32 actionId);
    error RecoveryInFlight(bytes32 actionId);
    error EmptyPayload();
    error UnknownAction(bytes32 actionId);
    error ResultAlreadyConsumed(bytes32 actionId);
    error ActionFailed(uint8 status);
    error InvalidSignature();
    error ResultMismatch();
    error StaleEpoch(uint64 supplied, uint64 expected);
    error EpochGap(uint64 supplied, uint64 expected);
    error CompetingFork(bytes32 suppliedParent, bytes32 expectedParent);
    error InvalidStateRoot();
    error SnapshotDigestMismatch();
    error RecoveryMustBePaused();
    error RecoveryNotArmed();

    event ExtensionConfigured(uint256 indexed extensionId);
    event MachinesConfigured(address indexed activeTee, address indexed recoveryTee, uint64 epoch, bytes32 stateRoot);
    event SnapshotRequested(
        bytes32 indexed actionId,
        uint64 indexed nonce,
        uint64 indexed epoch,
        address sourceTee,
        address recoveryTee,
        bytes32 parentRoot
    );
    event SnapshotCommitted(
        bytes32 indexed actionId,
        uint64 indexed epoch,
        bytes32 indexed stateRoot,
        bytes32 parentRoot,
        bytes32 ciphertextDigest,
        address sourceTee,
        address recoveryTee
    );
    event SnapshotFailed(bytes32 indexed actionId, address indexed sourceTee, uint64 indexed nonce);
    event SnapshotAbandoned(bytes32 indexed actionId, address indexed sourceTee, uint64 indexed nonce);
    event RecoveryRequested(
        bytes32 indexed actionId,
        address indexed recoveryTee,
        uint64 indexed epoch,
        bytes32 stateRoot,
        bytes32 ciphertextDigest
    );
    event RecoveryArmed(bytes32 indexed actionId, address indexed recoveryTee, uint64 epoch, bytes32 stateRoot);
    event RecoveryFailed(bytes32 indexed actionId, address indexed recoveryTee, uint64 indexed epoch);
    event RecoveryAbandoned(bytes32 indexed actionId, address indexed recoveryTee, uint64 indexed epoch);
    event RecoveryActivated(address indexed previousTee, address indexed activeTee, uint64 epoch, bytes32 stateRoot);

    IFlareTeeManager public immutable teeManager;
    address public immutable owner;
    bytes32 public immutable applicationId;
    bytes32 public immutable genesisRoot;

    uint256 public extensionId;
    address public activeTee;
    address public recoveryTee;
    uint64 public latestEpoch;
    uint64 public nextNonce = 1;
    bytes32 public latestParentRoot;
    bytes32 public latestStateRoot;
    bytes32 public latestCiphertextDigest;
    bool public recoveryArmed;
    bytes32 public pendingSnapshotAction;
    bytes32 public pendingRecoveryAction;

    mapping(address teeId => ExpectedState state) public expectedState;
    mapping(bytes32 actionId => PendingSnapshot snapshot) public pendingSnapshots;
    mapping(bytes32 actionId => PendingRecovery recovery) public pendingRecoveries;
    mapping(bytes32 actionId => bool consumed) public consumedResults;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(IFlareTeeManager manager, bytes32 appId) {
        if (address(manager) == address(0)) revert ZeroAddress();
        teeManager = manager;
        owner = msg.sender;
        applicationId = appId;
        // The literal is shorter than 32 bytes and intentionally right-padded with zeros.
        // forge-lint: disable-next-line(unsafe-typecast)
        genesisRoot = keccak256(abi.encode(appId, bytes32("CONTINUITY_GENESIS")));
        latestStateRoot = genesisRoot;
    }

    /// @notice Binds this deployed controller to its registered FCC extension.
    function configureExtension(uint256 newExtensionId) external onlyOwner {
        if (extensionId != 0) revert ExtensionAlreadyConfigured();
        if (newExtensionId == 0) revert ExtensionNotConfigured();
        if (teeManager.getTeeExtensionInstructionsSender(newExtensionId) != address(this)) {
            revert InvalidInstructionsSender();
        }
        if (teeManager.getTeeExtensionStateVerifier(newExtensionId) != address(this)) {
            revert InvalidStateVerifier();
        }
        extensionId = newExtensionId;
        emit ExtensionConfigured(newExtensionId);
    }

    /// @notice Sets the first machine pair while both still attest the deterministic genesis state.
    function configureMachines(address initialActiveTee, address initialRecoveryTee) external onlyOwner {
        _requireExtensionConfigured();
        if (
            initialActiveTee == address(0) || initialRecoveryTee == address(0) || initialActiveTee == initialRecoveryTee
                || activeTee != address(0)
        ) {
            revert InvalidMachinePair();
        }
        _requireExtension(initialActiveTee);
        _requireExtension(initialRecoveryTee);
        _requireStatus(initialActiveTee, TEE_STATUS_INITIALIZED);
        _requireStatus(initialRecoveryTee, TEE_STATUS_INITIALIZED);

        activeTee = initialActiveTee;
        recoveryTee = initialRecoveryTee;
        expectedState[initialActiveTee] = ExpectedState(0, genesisRoot, true);
        expectedState[initialRecoveryTee] = ExpectedState(0, genesisRoot, true);

        emit MachinesConfigured(initialActiveTee, initialRecoveryTee, 0, genesisRoot);
    }

    /// @notice Sends one mutation to the exact active TEE and records the lineage it must extend.
    function requestSnapshot(bytes calldata encryptedEntry) external payable returns (bytes32 actionId) {
        _requireMachinesConfigured();
        if (encryptedEntry.length == 0) revert EmptyPayload();
        if (pendingSnapshotAction != bytes32(0)) revert SnapshotInFlight(pendingSnapshotAction);
        if (pendingRecoveryAction != bytes32(0) || recoveryArmed) revert RecoveryInFlight(pendingRecoveryAction);
        _requireProduction(activeTee);
        _requireProduction(recoveryTee);

        uint64 nonce = nextNonce;
        uint64 epoch = latestEpoch + 1;
        bytes32 parentRoot = latestStateRoot;
        bytes memory message = abi.encode(applicationId, nonce, epoch, parentRoot, recoveryTee, encryptedEntry);

        actionId = _sendInstruction(activeTee, OP_SNAPSHOT, message);
        pendingSnapshots[actionId] = PendingSnapshot({
            sourceTee: activeTee,
            recoveryTee: recoveryTee,
            nonce: nonce,
            epoch: epoch,
            parentRoot: parentRoot,
            exists: true
        });
        pendingSnapshotAction = actionId;

        emit SnapshotRequested(actionId, nonce, epoch, activeTee, recoveryTee, parentRoot);
    }

    /// @notice Accepts a real FCC-signed snapshot result if it is the next unique lineage node.
    function commitSnapshot(
        bytes calldata resultData,
        bytes32 actionId,
        string calldata submissionTag,
        uint8 status,
        bytes calldata signature
    ) external {
        if (consumedResults[actionId]) revert ResultAlreadyConsumed(actionId);
        PendingSnapshot memory pending = pendingSnapshots[actionId];
        if (!pending.exists) revert UnknownAction(actionId);
        if (status != ACTION_SUCCESS) revert ActionFailed(status);
        if (_recoverActionSigner(resultData, actionId, submissionTag, status, signature) != pending.sourceTee) {
            revert InvalidSignature();
        }

        SnapshotResult memory result = abi.decode(resultData, (SnapshotResult));
        if (
            result.applicationId != applicationId || result.sourceTee != pending.sourceTee
                || result.recoveryTee != pending.recoveryTee || result.nonce != pending.nonce
        ) {
            revert ResultMismatch();
        }
        _requireExtension(result.sourceTee);
        _requireProduction(result.sourceTee);
        _validateNextNode(result.epoch, result.parentRoot);
        if (result.epoch != pending.epoch || result.parentRoot != pending.parentRoot) revert ResultMismatch();
        if (result.stateRoot == bytes32(0) || result.stateRoot == result.parentRoot) revert InvalidStateRoot();
        if (result.ciphertext.length == 0) revert EmptyPayload();

        bytes32 ciphertextDigest = keccak256(result.ciphertext);
        _clearSnapshot(actionId);
        latestEpoch = result.epoch;
        latestParentRoot = result.parentRoot;
        latestStateRoot = result.stateRoot;
        latestCiphertextDigest = ciphertextDigest;
        expectedState[result.sourceTee] = ExpectedState(result.epoch, result.stateRoot, true);

        emit SnapshotCommitted(
            actionId,
            result.epoch,
            result.stateRoot,
            result.parentRoot,
            ciphertextDigest,
            result.sourceTee,
            result.recoveryTee
        );
    }

    /// @notice Clears a terminal FCC error result without advancing the state lineage.
    function failSnapshot(
        bytes calldata resultData,
        bytes32 actionId,
        string calldata submissionTag,
        uint8 status,
        bytes calldata signature
    ) external {
        if (consumedResults[actionId]) revert ResultAlreadyConsumed(actionId);
        PendingSnapshot memory pending = pendingSnapshots[actionId];
        if (!pending.exists) revert UnknownAction(actionId);
        if (status != ACTION_ERROR) revert ActionFailed(status);
        if (_recoverActionSigner(resultData, actionId, submissionTag, status, signature) != pending.sourceTee) {
            revert InvalidSignature();
        }

        _clearSnapshot(actionId);
        emit SnapshotFailed(actionId, pending.sourceTee, pending.nonce);
    }

    /// @notice Clears a request with no result only after its source TEE has left production.
    function abandonSnapshot(bytes32 actionId) external onlyOwner {
        PendingSnapshot memory pending = pendingSnapshots[actionId];
        if (!pending.exists) revert UnknownAction(actionId);
        uint8 actual = teeManager.getTeeMachineStatus(pending.sourceTee);
        if (actual == TEE_STATUS_PRODUCTION) {
            revert WrongMachineStatus(pending.sourceTee, TEE_STATUS_PAUSED, actual);
        }

        _clearSnapshot(actionId);
        emit SnapshotAbandoned(actionId, pending.sourceTee, pending.nonce);
    }

    /// @notice Sends the latest committed ciphertext to the designated recovery TEE.
    function requestRecovery(bytes calldata ciphertext) external payable returns (bytes32 actionId) {
        _requireMachinesConfigured();
        if (ciphertext.length == 0) revert EmptyPayload();
        if (pendingSnapshotAction != bytes32(0)) revert SnapshotInFlight(pendingSnapshotAction);
        if (pendingRecoveryAction != bytes32(0) || recoveryArmed) revert RecoveryInFlight(pendingRecoveryAction);
        if (keccak256(ciphertext) != latestCiphertextDigest) revert SnapshotDigestMismatch();
        _requireProduction(recoveryTee);
        _requireExtension(recoveryTee);

        bytes memory message =
            abi.encode(applicationId, latestEpoch, latestStateRoot, latestCiphertextDigest, ciphertext);
        actionId = _sendInstruction(recoveryTee, OP_RESTORE, message);
        pendingRecoveries[actionId] = PendingRecovery({
            recoveryTee: recoveryTee,
            epoch: latestEpoch,
            stateRoot: latestStateRoot,
            ciphertextDigest: latestCiphertextDigest,
            exists: true
        });
        pendingRecoveryAction = actionId;

        emit RecoveryRequested(actionId, recoveryTee, latestEpoch, latestStateRoot, latestCiphertextDigest);
    }

    /// @notice Arms the verifier only after a signed restore result and an explicit manager pause.
    function armRecovery(
        bytes calldata resultData,
        bytes32 actionId,
        string calldata submissionTag,
        uint8 status,
        bytes calldata signature
    ) external {
        if (consumedResults[actionId]) revert ResultAlreadyConsumed(actionId);
        PendingRecovery memory pending = pendingRecoveries[actionId];
        if (!pending.exists) revert UnknownAction(actionId);
        if (status != ACTION_SUCCESS) revert ActionFailed(status);
        if (_recoverActionSigner(resultData, actionId, submissionTag, status, signature) != pending.recoveryTee) {
            revert InvalidSignature();
        }

        RecoveryResult memory result = abi.decode(resultData, (RecoveryResult));
        if (
            result.applicationId != applicationId || result.recoveryTee != pending.recoveryTee
                || result.epoch != pending.epoch || result.stateRoot != pending.stateRoot
                || result.ciphertextDigest != pending.ciphertextDigest || result.epoch != latestEpoch
                || result.stateRoot != latestStateRoot || result.ciphertextDigest != latestCiphertextDigest
        ) {
            revert ResultMismatch();
        }
        _requireExtension(result.recoveryTee);
        uint8 statusNow = teeManager.getTeeMachineStatus(result.recoveryTee);
        if (statusNow != TEE_STATUS_PAUSED) revert RecoveryMustBePaused();

        _clearRecovery(actionId);
        expectedState[result.recoveryTee] = ExpectedState(result.epoch, result.stateRoot, true);
        recoveryArmed = true;
        emit RecoveryArmed(actionId, result.recoveryTee, result.epoch, result.stateRoot);
    }

    /// @notice Clears a terminal FCC restore error without arming the replacement TEE.
    function failRecovery(
        bytes calldata resultData,
        bytes32 actionId,
        string calldata submissionTag,
        uint8 status,
        bytes calldata signature
    ) external {
        if (consumedResults[actionId]) revert ResultAlreadyConsumed(actionId);
        PendingRecovery memory pending = pendingRecoveries[actionId];
        if (!pending.exists) revert UnknownAction(actionId);
        if (status != ACTION_ERROR) revert ActionFailed(status);
        if (_recoverActionSigner(resultData, actionId, submissionTag, status, signature) != pending.recoveryTee) {
            revert InvalidSignature();
        }

        _clearRecovery(actionId);
        emit RecoveryFailed(actionId, pending.recoveryTee, pending.epoch);
    }

    /// @notice Clears a restore with no result only after its target TEE has left production.
    function abandonRecovery(bytes32 actionId) external onlyOwner {
        PendingRecovery memory pending = pendingRecoveries[actionId];
        if (!pending.exists) revert UnknownAction(actionId);
        uint8 actual = teeManager.getTeeMachineStatus(pending.recoveryTee);
        if (actual == TEE_STATUS_PRODUCTION) {
            revert WrongMachineStatus(pending.recoveryTee, TEE_STATUS_PAUSED, actual);
        }

        _clearRecovery(actionId);
        emit RecoveryAbandoned(actionId, pending.recoveryTee, pending.epoch);
    }

    /// @notice Activates a replacement only after the manager returned it to production.
    /// @dev The PAUSED requirement in armRecovery means this production transition needs a fresh
    /// availability proof, and that proof must pass verifyTeeState with the restored root.
    function activateRecovery() external {
        if (!recoveryArmed) revert RecoveryNotArmed();
        _requireProduction(recoveryTee);
        ExpectedState memory expected = expectedState[recoveryTee];
        if (!expected.exists || expected.epoch != latestEpoch || expected.root != latestStateRoot) {
            revert ResultMismatch();
        }

        address previous = activeTee;
        activeTee = recoveryTee;
        recoveryTee = previous;
        recoveryArmed = false;
        emit RecoveryActivated(previous, activeTee, latestEpoch, latestStateRoot);
    }

    /// @notice Live FlareTeeManager callback used during FCC availability verification.
    function verifyTeeState(address teeId, bytes32 stateVersion, bytes calldata state)
        external
        view
        returns (bool isValid)
    {
        if (stateVersion != STATE_VERSION || state.length != 96) return false;

        bytes32 appId;
        uint256 epochWord;
        bytes32 stateRoot;
        assembly {
            appId := calldataload(state.offset)
            epochWord := calldataload(add(state.offset, 32))
            stateRoot := calldataload(add(state.offset, 64))
        }
        if (appId != applicationId || epochWord > type(uint64).max) return false;

        ExpectedState memory expected = expectedState[teeId];
        // The range guard above proves epochWord fits uint64.
        // forge-lint: disable-next-line(unsafe-typecast)
        return expected.exists && expected.epoch == uint64(epochWord) && expected.root == stateRoot;
    }

    function _sendInstruction(address target, bytes32 command, bytes memory message)
        private
        returns (bytes32 actionId)
    {
        address[] memory teeIds = new address[](1);
        teeIds[0] = target;
        address[] memory cosigners = new address[](0);
        IFlareTeeManager.TeeInstructionParams memory params = IFlareTeeManager.TeeInstructionParams({
            opType: OP_TYPE,
            opCommand: command,
            message: message,
            cosigners: cosigners,
            cosignersThreshold: 0,
            claimBackAddress: msg.sender
        });
        actionId = teeManager.sendInstructions{ value: msg.value }(teeIds, params);
    }

    function _clearSnapshot(bytes32 actionId) private {
        consumedResults[actionId] = true;
        delete pendingSnapshots[actionId];
        pendingSnapshotAction = bytes32(0);
        nextNonce++;
    }

    function _clearRecovery(bytes32 actionId) private {
        consumedResults[actionId] = true;
        delete pendingRecoveries[actionId];
        pendingRecoveryAction = bytes32(0);
    }

    function _validateNextNode(uint64 epoch, bytes32 parentRoot) private view {
        uint64 expectedEpoch = latestEpoch + 1;
        if (epoch == latestEpoch && parentRoot == latestParentRoot && parentRoot != latestStateRoot) {
            revert CompetingFork(parentRoot, latestStateRoot);
        }
        if (epoch < expectedEpoch) revert StaleEpoch(epoch, expectedEpoch);
        if (epoch > expectedEpoch) revert EpochGap(epoch, expectedEpoch);
        if (parentRoot != latestStateRoot) revert CompetingFork(parentRoot, latestStateRoot);
    }

    function _recoverActionSigner(
        bytes calldata resultData,
        bytes32 actionId,
        string calldata submissionTag,
        uint8 status,
        bytes calldata signature
    ) private view returns (address signer) {
        if (signature.length != 65) revert InvalidSignature();
        bytes32 resultHash =
            keccak256(abi.encodePacked(keccak256(resultData), actionId, keccak256(bytes(submissionTag)), status));
        bytes32 payloadHash = keccak256(abi.encode(TEE_ACTION_RESULT_PREFIX, block.chainid, resultHash));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (v < 27) v += 27;
        if ((v != 27 && v != 28) || uint256(s) > SECP256K1_HALF_ORDER) revert InvalidSignature();
        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
    }

    function _requireExtensionConfigured() private view {
        if (extensionId == 0) revert ExtensionNotConfigured();
    }

    function _requireMachinesConfigured() private view {
        _requireExtensionConfigured();
        if (activeTee == address(0) || recoveryTee == address(0)) revert MachinesNotConfigured();
    }

    function _requireExtension(address teeId) private view {
        if (teeManager.getExtensionId(teeId) != extensionId) revert WrongExtension(teeId);
    }

    function _requireProduction(address teeId) private view {
        _requireExtension(teeId);
        _requireStatus(teeId, TEE_STATUS_PRODUCTION);
        IFlareTeeManager.TeeMachineWithAttestationData memory machine =
            teeManager.getTeeMachineWithAttestationData(teeId);
        if (
            machine.teeId != teeId
                || !teeManager.isCodeHashPlatformSupported(extensionId, machine.codeHash, machine.platform)
        ) {
            revert UnsupportedMachineVersion(teeId);
        }
    }

    function _requireStatus(address teeId, uint8 expected) private view {
        uint8 actual = teeManager.getTeeMachineStatus(teeId);
        if (actual != expected) {
            revert WrongMachineStatus(teeId, expected, actual);
        }
    }
}
