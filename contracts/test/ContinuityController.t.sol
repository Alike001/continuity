// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ContinuityController } from "../src/ContinuityController.sol";
import { IFlareTeeManager } from "../src/interfaces/IFlareTeeManager.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address keyAddr);
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes calldata revertData) external;
    function prank(address sender) external;
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract MockFlareTeeManager is IFlareTeeManager {
    uint256 public sequence;
    address public instructionsSender;
    address public stateVerifier;
    address public lastTarget;
    bytes32 public lastOpType;
    bytes32 public lastOpCommand;
    bytes public lastMessage;
    uint256 public lastValue;
    bytes32 public constant CODE_HASH = keccak256("continuity-code");
    // The literal is shorter than 32 bytes and intentionally right-padded with zeros.
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant PLATFORM = bytes32("SIMULATED_TEE");
    bool public codeSupported = true;

    mapping(address teeId => uint256 extensionId) public extensions;
    mapping(address teeId => uint8 status) public statuses;

    function setInstructionsSender(address sender) external {
        instructionsSender = sender;
    }

    function setStateVerifier(address verifier) external {
        stateVerifier = verifier;
    }

    function setMachine(address teeId, uint256 extensionId, uint8 status) external {
        extensions[teeId] = extensionId;
        statuses[teeId] = status;
    }

    function setStatus(address teeId, uint8 status) external {
        statuses[teeId] = status;
    }

    function setCodeSupported(bool supported) external {
        codeSupported = supported;
    }

    function sendInstructions(address[] calldata teeIds, TeeInstructionParams calldata params)
        external
        payable
        returns (bytes32 instructionId)
    {
        require(msg.sender == instructionsSender, "wrong sender");
        require(teeIds.length == 1, "wrong targets");
        sequence++;
        instructionId = keccak256(abi.encode(sequence, teeIds[0], params.opCommand));
        lastTarget = teeIds[0];
        lastOpType = params.opType;
        lastOpCommand = params.opCommand;
        lastMessage = params.message;
        lastValue = msg.value;
    }

    function getExtensionId(address teeId) external view returns (uint256) {
        return extensions[teeId];
    }

    function getTeeMachineStatus(address teeId) external view returns (uint8) {
        return statuses[teeId];
    }

    function getPublicKey(address teeId) external pure returns (PublicKey memory publicKey) {
        publicKey = PublicKey({ x: bytes32(uint256(uint160(teeId)) + 1), y: bytes32(uint256(uint160(teeId)) + 2) });
    }

    function getTeeMachineWithAttestationData(address teeId)
        external
        pure
        returns (TeeMachineWithAttestationData memory machine)
    {
        machine = TeeMachineWithAttestationData({
            teeId: teeId, initialTeeId: address(0), url: "https://tee.invalid", codeHash: CODE_HASH, platform: PLATFORM
        });
    }

    function getTeeExtensionInstructionsSender(uint256) external view returns (address) {
        return instructionsSender;
    }

    function getTeeExtensionStateVerifier(uint256) external view returns (address) {
        return stateVerifier;
    }

    function isCodeHashPlatformSupported(uint256, bytes32, bytes32) external view returns (bool supported) {
        return codeSupported;
    }
}

contract ContinuityControllerTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 private constant APP_ID = keccak256("sealed-journal");
    // The literal is shorter than 32 bytes and intentionally right-padded with zeros.
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 private constant RESULT_PREFIX = bytes32("TEE_ACTION_RESULT");
    string private constant TAG = "submit";
    uint256 private constant EXTENSION_ID = 65_536;
    uint256 private constant ACTIVE_KEY = 0xA11CE;
    uint256 private constant RECOVERY_KEY = 0xB0B;
    uint8 private constant INITIALIZED = 1;
    uint8 private constant PRODUCTION = 2;
    uint8 private constant PAUSED = 4;

    MockFlareTeeManager private manager;
    ContinuityController private controller;
    address private activeTee;
    address private recoveryTee;

    function setUp() public {
        activeTee = vm.addr(ACTIVE_KEY);
        recoveryTee = vm.addr(RECOVERY_KEY);
        manager = new MockFlareTeeManager();
        controller = new ContinuityController(manager, APP_ID);
        manager.setInstructionsSender(address(controller));
        manager.setStateVerifier(address(controller));
        manager.setMachine(activeTee, EXTENSION_ID, INITIALIZED);
        manager.setMachine(recoveryTee, EXTENSION_ID, INITIALIZED);
        controller.configureExtension(EXTENSION_ID);
        controller.configureMachines(activeTee, recoveryTee);
        manager.setStatus(activeTee, PRODUCTION);
        manager.setStatus(recoveryTee, PRODUCTION);
    }

    function testInitialStateAndCanonicalAttestation() public view {
        bytes32 root = controller.genesisRoot();
        _assertEq(controller.latestEpoch(), 0, "wrong genesis epoch");
        _assertEq(controller.latestStateRoot(), root, "wrong genesis root");
        _assertTrue(
            controller.verifyTeeState(activeTee, controller.STATE_VERSION(), abi.encode(APP_ID, uint64(0), root)),
            "genesis state rejected"
        );
        _assertTrue(
            controller.verifyTeeState(recoveryTee, controller.STATE_VERSION(), abi.encode(APP_ID, uint64(0), root)),
            "recovery genesis rejected"
        );
    }

    function testSnapshotRequestAndSignedCommit() public {
        bytes memory encryptedEntry = hex"010203";
        bytes32 actionId = controller.requestSnapshot{ value: 7 }(encryptedEntry);
        _assertEq(manager.lastTarget(), activeTee, "wrong target");
        _assertEq(manager.lastOpType(), controller.OP_TYPE(), "wrong op type");
        _assertEq(manager.lastOpCommand(), controller.OP_SNAPSHOT(), "wrong command");
        _assertEq(manager.lastValue(), 7, "fee not forwarded");
        _assertSnapshotMessage(encryptedEntry);

        bytes32 parent = controller.genesisRoot();
        bytes32 root = keccak256("state-1");
        bytes memory ciphertext = hex"c0ffee";
        bytes memory data = _snapshotData(actionId, 1, 1, parent, root, ciphertext);
        controller.commitSnapshot(data, actionId, TAG, 1, _sign(ACTIVE_KEY, data, actionId, 1));

        _assertEq(controller.latestEpoch(), 1, "epoch not advanced");
        _assertEq(controller.latestParentRoot(), parent, "parent not stored");
        _assertEq(controller.latestStateRoot(), root, "root not stored");
        _assertEq(controller.latestCiphertextDigest(), keccak256(ciphertext), "digest not stored");
        _assertTrue(
            controller.verifyTeeState(activeTee, controller.STATE_VERSION(), abi.encode(APP_ID, uint64(1), root)),
            "committed active state rejected"
        );
    }

    function _assertSnapshotMessage(bytes memory encryptedEntry) private view {
        (
            bytes32 messageApplicationId,
            uint64 messageNonce,
            uint64 messageEpoch,
            bytes32 messageParent,
            address messageRecoveryTee,
            bytes32 messagePublicKeyX,
            bytes32 messagePublicKeyY,
            bytes memory messageEncryptedEntry
        ) = abi.decode(manager.lastMessage(), (bytes32, uint64, uint64, bytes32, address, bytes32, bytes32, bytes));
        _assertEq(messageApplicationId, APP_ID, "wrong message application");
        _assertEq(messageNonce, 1, "wrong message nonce");
        _assertEq(messageEpoch, 1, "wrong message epoch");
        _assertEq(messageParent, controller.genesisRoot(), "wrong message parent");
        _assertEq(messageRecoveryTee, recoveryTee, "wrong message recovery TEE");
        _assertEq(messagePublicKeyX, bytes32(uint256(uint160(recoveryTee)) + 1), "wrong public key x");
        _assertEq(messagePublicKeyY, bytes32(uint256(uint160(recoveryTee)) + 2), "wrong public key y");
        _assertEq(keccak256(messageEncryptedEntry), keccak256(encryptedEntry), "wrong encrypted entry");
    }

    function testRejectsReplayedResult() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        bytes memory data = _snapshotData(actionId, 1, 1, controller.genesisRoot(), keccak256("state-1"), hex"11");
        bytes memory signature = _sign(ACTIVE_KEY, data, actionId, 1);
        controller.commitSnapshot(data, actionId, TAG, 1, signature);

        vm.expectRevert(abi.encodeWithSelector(ContinuityController.ResultAlreadyConsumed.selector, actionId));
        controller.commitSnapshot(data, actionId, TAG, 1, signature);
    }

    function testRejectsWrongTeeSignature() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        bytes memory data = _snapshotData(actionId, 1, 1, controller.genesisRoot(), keccak256("state-1"), hex"11");
        vm.expectRevert(ContinuityController.InvalidSignature.selector);
        controller.commitSnapshot(data, actionId, TAG, 1, _sign(RECOVERY_KEY, data, actionId, 1));
    }

    function testRejectsFailedAction() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        bytes memory data = _snapshotData(actionId, 1, 1, controller.genesisRoot(), keccak256("state-1"), hex"11");
        vm.expectRevert(abi.encodeWithSelector(ContinuityController.ActionFailed.selector, uint8(0)));
        controller.commitSnapshot(data, actionId, TAG, 0, _sign(ACTIVE_KEY, data, actionId, 0));
    }

    function testRejectsStaleSnapshot() public {
        _commitFirstSnapshot();
        bytes32 actionId = controller.requestSnapshot(hex"02");
        bytes memory data = _snapshotData(actionId, 2, 1, controller.latestStateRoot(), keccak256("stale"), hex"22");
        vm.expectRevert(abi.encodeWithSelector(ContinuityController.StaleEpoch.selector, uint64(1), uint64(2)));
        controller.commitSnapshot(data, actionId, TAG, 1, _sign(ACTIVE_KEY, data, actionId, 1));
    }

    function testRejectsEpochGap() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        bytes memory data = _snapshotData(actionId, 1, 2, controller.genesisRoot(), keccak256("future"), hex"11");
        vm.expectRevert(abi.encodeWithSelector(ContinuityController.EpochGap.selector, uint64(2), uint64(1)));
        controller.commitSnapshot(data, actionId, TAG, 1, _sign(ACTIVE_KEY, data, actionId, 1));
    }

    function testRejectsCompetingBranch() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        bytes32 wrongParent = keccak256("other-parent");
        bytes memory data = _snapshotData(actionId, 1, 1, wrongParent, keccak256("branch-b"), hex"bb");
        vm.expectRevert(
            abi.encodeWithSelector(
                ContinuityController.CompetingFork.selector, wrongParent, controller.latestStateRoot()
            )
        );
        controller.commitSnapshot(data, actionId, TAG, 1, _sign(ACTIVE_KEY, data, actionId, 1));
    }

    function testRejectsSecondSnapshotWhileOneIsInFlight() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        vm.expectRevert(abi.encodeWithSelector(ContinuityController.SnapshotInFlight.selector, actionId));
        controller.requestSnapshot(hex"02");
    }

    function testVerifierRejectsMalformedOrUnexpectedState() public view {
        bytes32 root = controller.genesisRoot();
        _assertFalse(
            // forge-lint: disable-next-line(unsafe-typecast)
            controller.verifyTeeState(activeTee, bytes32("WRONG"), abi.encode(APP_ID, uint64(0), root)),
            "bad version accepted"
        );
        _assertFalse(controller.verifyTeeState(activeTee, controller.STATE_VERSION(), hex"01"), "short state accepted");
        _assertFalse(
            controller.verifyTeeState(
                activeTee, controller.STATE_VERSION(), abi.encode(APP_ID, uint256(type(uint64).max) + 1, root)
            ),
            "wide epoch accepted"
        );
        _assertFalse(
            controller.verifyTeeState(
                activeTee, controller.STATE_VERSION(), abi.encode(APP_ID, uint64(0), keccak256("wrong"))
            ),
            "wrong root accepted"
        );
        _assertFalse(
            controller.verifyTeeState(address(0x1234), controller.STATE_VERSION(), abi.encode(APP_ID, uint64(0), root)),
            "unknown TEE accepted"
        );
    }

    function testRecoveryRequiresExactCiphertextAndFreshAvailabilityTransition() public {
        bytes memory ciphertext = _commitFirstSnapshot();

        vm.expectRevert(ContinuityController.SnapshotDigestMismatch.selector);
        controller.requestRecovery(hex"dead");

        bytes32 actionId = controller.requestRecovery(ciphertext);
        _assertEq(manager.lastTarget(), recoveryTee, "restore sent to wrong TEE");
        _assertEq(manager.lastOpCommand(), controller.OP_RESTORE(), "wrong restore command");

        bytes memory data = _recoveryData(1, controller.latestStateRoot(), keccak256(ciphertext));
        bytes memory signature = _sign(RECOVERY_KEY, data, actionId, 1);
        vm.expectRevert(ContinuityController.RecoveryMustBePaused.selector);
        controller.armRecovery(data, actionId, TAG, 1, signature);

        manager.setStatus(recoveryTee, PAUSED);
        controller.armRecovery(data, actionId, TAG, 1, signature);
        _assertTrue(controller.recoveryArmed(), "recovery not armed");
        _assertTrue(
            controller.verifyTeeState(
                recoveryTee,
                controller.STATE_VERSION(),
                abi.encode(APP_ID, controller.latestEpoch(), controller.latestStateRoot())
            ),
            "restored state rejected"
        );

        vm.expectRevert(
            abi.encodeWithSelector(ContinuityController.WrongMachineStatus.selector, recoveryTee, PRODUCTION, PAUSED)
        );
        controller.activateRecovery();

        manager.setStatus(recoveryTee, PRODUCTION);
        controller.activateRecovery();
        _assertEq(controller.activeTee(), recoveryTee, "replacement not active");
        _assertEq(controller.recoveryTee(), activeTee, "old active not designated recovery");
        _assertFalse(controller.recoveryArmed(), "recovery remained armed");
    }

    function testRejectsRecoveryResultForDifferentRoot() public {
        bytes memory ciphertext = _commitFirstSnapshot();
        bytes32 actionId = controller.requestRecovery(ciphertext);
        manager.setStatus(recoveryTee, PAUSED);
        bytes memory data = _recoveryData(1, keccak256("wrong"), keccak256(ciphertext));
        vm.expectRevert(ContinuityController.ResultMismatch.selector);
        controller.armRecovery(data, actionId, TAG, 1, _sign(RECOVERY_KEY, data, actionId, 1));
    }

    function testRejectsWrongExtensionAndNonProductionMachine() public {
        manager.setMachine(activeTee, EXTENSION_ID + 1, PRODUCTION);
        vm.expectRevert(abi.encodeWithSelector(ContinuityController.WrongExtension.selector, activeTee));
        controller.requestSnapshot(hex"01");

        manager.setMachine(activeTee, EXTENSION_ID, PAUSED);
        vm.expectRevert(
            abi.encodeWithSelector(ContinuityController.WrongMachineStatus.selector, activeTee, PRODUCTION, PAUSED)
        );
        controller.requestSnapshot(hex"01");
    }

    function testRejectsUnsupportedMachineVersion() public {
        manager.setCodeSupported(false);
        vm.expectRevert(abi.encodeWithSelector(ContinuityController.UnsupportedMachineVersion.selector, activeTee));
        controller.requestSnapshot(hex"01");
    }

    function testTerminalErrorSnapshotReleasesGateAndConsumesResult() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        bytes memory data = bytes("extension rejected input");
        bytes memory signature = _sign(ACTIVE_KEY, data, actionId, 0);
        controller.failSnapshot(data, actionId, TAG, 0, signature);
        _assertEq(controller.pendingSnapshotAction(), bytes32(0), "snapshot gate not cleared");

        vm.expectRevert(abi.encodeWithSelector(ContinuityController.ResultAlreadyConsumed.selector, actionId));
        controller.failSnapshot(data, actionId, TAG, 0, signature);
        controller.requestSnapshot(hex"02");
    }

    function testSnapshotAbandonRequiresStoppedTee() public {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(ContinuityController.WrongMachineStatus.selector, activeTee, PAUSED, PRODUCTION)
        );
        controller.abandonSnapshot(actionId);

        manager.setStatus(activeTee, PAUSED);
        controller.abandonSnapshot(actionId);
        _assertEq(controller.pendingSnapshotAction(), bytes32(0), "snapshot gate not cleared");
    }

    function testTerminalErrorRecoveryReleasesGate() public {
        bytes memory ciphertext = _commitFirstSnapshot();
        bytes32 actionId = controller.requestRecovery(ciphertext);
        bytes memory data = bytes("restore rejected");
        controller.failRecovery(data, actionId, TAG, 0, _sign(RECOVERY_KEY, data, actionId, 0));
        _assertEq(controller.pendingRecoveryAction(), bytes32(0), "recovery gate not cleared");
    }

    function testRecoveryAbandonRequiresStoppedTee() public {
        bytes memory ciphertext = _commitFirstSnapshot();
        bytes32 actionId = controller.requestRecovery(ciphertext);
        vm.expectRevert(
            abi.encodeWithSelector(ContinuityController.WrongMachineStatus.selector, recoveryTee, PAUSED, PRODUCTION)
        );
        controller.abandonRecovery(actionId);

        manager.setStatus(recoveryTee, PAUSED);
        controller.abandonRecovery(actionId);
        _assertEq(controller.pendingRecoveryAction(), bytes32(0), "recovery gate not cleared");
    }

    function testInitialMachinesRequireFreshAvailabilityPath() public {
        MockFlareTeeManager otherManager = new MockFlareTeeManager();
        ContinuityController other = new ContinuityController(otherManager, APP_ID);
        otherManager.setInstructionsSender(address(other));
        otherManager.setStateVerifier(address(other));
        otherManager.setMachine(activeTee, EXTENSION_ID, PRODUCTION);
        otherManager.setMachine(recoveryTee, EXTENSION_ID, INITIALIZED);
        other.configureExtension(EXTENSION_ID);

        vm.expectRevert(
            abi.encodeWithSelector(ContinuityController.WrongMachineStatus.selector, activeTee, INITIALIZED, PRODUCTION)
        );
        other.configureMachines(activeTee, recoveryTee);
    }

    function testOnlyOwnerCanConfigure() public {
        MockFlareTeeManager otherManager = new MockFlareTeeManager();
        ContinuityController other = new ContinuityController(otherManager, APP_ID);
        vm.prank(address(0xBEEF));
        vm.expectRevert(ContinuityController.NotOwner.selector);
        other.configureExtension(EXTENSION_ID);
    }

    function testConfigurationRequiresControllerAsStateVerifier() public {
        MockFlareTeeManager otherManager = new MockFlareTeeManager();
        ContinuityController other = new ContinuityController(otherManager, APP_ID);
        otherManager.setInstructionsSender(address(other));
        otherManager.setStateVerifier(address(0xBEEF));

        vm.expectRevert(ContinuityController.InvalidStateVerifier.selector);
        other.configureExtension(EXTENSION_ID);
    }

    function _commitFirstSnapshot() private returns (bytes memory ciphertext) {
        bytes32 actionId = controller.requestSnapshot(hex"01");
        ciphertext = hex"c0ffee";
        bytes memory data = _snapshotData(actionId, 1, 1, controller.genesisRoot(), keccak256("state-1"), ciphertext);
        controller.commitSnapshot(data, actionId, TAG, 1, _sign(ACTIVE_KEY, data, actionId, 1));
    }

    function _snapshotData(bytes32, uint64 nonce, uint64 epoch, bytes32 parent, bytes32 root, bytes memory ciphertext)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(APP_ID, activeTee, recoveryTee, nonce, epoch, parent, root, ciphertext);
    }

    function _recoveryData(uint64 epoch, bytes32 root, bytes32 digest) private view returns (bytes memory) {
        return abi.encode(APP_ID, recoveryTee, epoch, root, digest);
    }

    function _sign(uint256 privateKey, bytes memory data, bytes32 actionId, uint8 status)
        private
        returns (bytes memory signature)
    {
        bytes32 resultHash = keccak256(abi.encodePacked(keccak256(data), actionId, keccak256(bytes(TAG)), status));
        bytes32 payloadHash = keccak256(abi.encode(RESULT_PREFIX, block.chainid, resultHash));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _assertTrue(bool condition, string memory reason) private pure {
        require(condition, reason);
    }

    function _assertFalse(bool condition, string memory reason) private pure {
        require(!condition, reason);
    }

    function _assertEq(bytes32 actual, bytes32 expected, string memory reason) private pure {
        require(actual == expected, reason);
    }

    function _assertEq(address actual, address expected, string memory reason) private pure {
        require(actual == expected, reason);
    }

    function _assertEq(uint256 actual, uint256 expected, string memory reason) private pure {
        require(actual == expected, reason);
    }
}
