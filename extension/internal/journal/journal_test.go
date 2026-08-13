package journal

import (
	"bytes"
	"crypto/ecdsa"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/flare-foundation/go-flare-common/pkg/tee/instruction"
	"github.com/flare-foundation/tee-node/pkg/types"
	"github.com/flare-foundation/tee-node/pkg/utils"
)

var testApplicationID = crypto.Keccak256Hash([]byte("sealed-journal"))

type keyDecrypter struct{ key *ecdsa.PrivateKey }

func (d keyDecrypter) Decrypt(ciphertext []byte) ([]byte, error) {
	return utils.Decrypt(ciphertext, d.key)
}

func TestGenesisMatchesControllerAndStateWireFormat(t *testing.T) {
	key := mustKey(t)
	extension := New(testApplicationID, crypto.PubkeyToAddress(key.PublicKey), keyDecrypter{key})
	expected := crypto.Keccak256Hash(
		mustPack(arguments("bytes32", "bytes32"), testApplicationID, utils.ToHash("CONTINUITY_GENESIS")),
	)
	if extension.State().StateRoot != expected {
		t.Fatalf("genesis mismatch: got %s want %s", extension.State().StateRoot, expected)
	}

	recorder := httptest.NewRecorder()
	extension.Handler().ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/state", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("state status: %d", recorder.Code)
	}
	var response map[string]json.RawMessage
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	var stateHex string
	if err := json.Unmarshal(response["state"], &stateHex); err != nil {
		t.Fatal(err)
	}
	if len(stateHex) != 2+96*2 || stateHex[:2] != "0x" {
		t.Fatalf("state is not canonical 96-byte hex: %q", stateHex)
	}
	var version string
	if err := json.Unmarshal(response["stateVersion"], &version); err != nil {
		t.Fatal(err)
	}
	if version != StateVersion.Hex() {
		t.Fatalf("version mismatch: %s", version)
	}
}

func TestSnapshotAndRestoreRoundTrip(t *testing.T) {
	primaryKey := mustKey(t)
	recoveryKey := mustKey(t)
	primary := New(testApplicationID, crypto.PubkeyToAddress(primaryKey.PublicKey), keyDecrypter{primaryKey})
	recovery := New(testApplicationID, crypto.PubkeyToAddress(recoveryKey.PublicKey), keyDecrypter{recoveryKey})

	entry := []byte("private incident note")
	encryptedEntry, err := utils.Encrypt(entry, &primaryKey.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	request := snapshotRequest{
		ApplicationID:  testApplicationID,
		Nonce:          1,
		Epoch:          1,
		ParentRoot:     primary.State().StateRoot,
		RecoveryTee:    crypto.PubkeyToAddress(recoveryKey.PublicKey),
		PublicKeyX:     common.BytesToHash(recoveryKey.PublicKey.X.Bytes()),
		PublicKeyY:     common.BytesToHash(recoveryKey.PublicKey.Y.Bytes()),
		EncryptedEntry: encryptedEntry,
	}
	action := snapshotAction(t, request, crypto.PubkeyToAddress(primaryKey.PublicKey))
	result := postAction(t, primary, action)
	assertEcho(t, result, action, OpType, OpSnapshot)
	if result.Status != statusSuccess {
		t.Fatalf("snapshot failed: %s", result.Log)
	}
	decodedResult := decodeSnapshotResult(t, result.Data)
	if decodedResult.StateRoot != primary.State().StateRoot || decodedResult.ParentRoot != request.ParentRoot {
		t.Fatal("snapshot result roots do not match extension state")
	}
	if !bytes.Equal(primary.State().Entries[0].Plaintext, entry) {
		t.Fatal("private entry was not committed")
	}

	restore := restoreRequest{
		ApplicationID:    testApplicationID,
		Epoch:            1,
		StateRoot:        decodedResult.StateRoot,
		CiphertextDigest: crypto.Keccak256Hash(decodedResult.Ciphertext),
		Ciphertext:       decodedResult.Ciphertext,
	}
	restoreActionValue := restoreAction(t, restore, crypto.PubkeyToAddress(recoveryKey.PublicKey))
	restoreResult := postAction(t, recovery, restoreActionValue)
	assertEcho(t, restoreResult, restoreActionValue, OpType, OpRestore)
	if restoreResult.Status != statusSuccess {
		t.Fatalf("restore failed: %s", restoreResult.Log)
	}
	if recovery.State().StateRoot != primary.State().StateRoot || !bytes.Equal(recovery.State().Entries[0].Plaintext, entry) {
		t.Fatal("restored state differs from primary")
	}
	decodedRecovery := decodeRecoveryResult(t, restoreResult.Data)
	if decodedRecovery.RecoveryTee != crypto.PubkeyToAddress(recoveryKey.PublicKey) || decodedRecovery.StateRoot != restore.StateRoot {
		t.Fatal("recovery result mismatch")
	}
}

func TestRootIsDeterministicAndSensitiveToOrder(t *testing.T) {
	state := State{
		ApplicationID: testApplicationID,
		Epoch:         2,
		NextEntryID:   3,
		NextNonce:     3,
		Entries:       []Entry{{ID: 1, Plaintext: []byte("a")}, {ID: 2, Plaintext: []byte("b")}},
	}
	first := Root(state)
	second := Root(cloneState(state))
	if first != second {
		t.Fatal("same state produced different roots")
	}
	state.Entries[0], state.Entries[1] = state.Entries[1], state.Entries[0]
	if Root(state) == first {
		t.Fatal("entry order did not affect root")
	}
}

func TestSnapshotResultEncodingMatchesSolidityFlatTuple(t *testing.T) {
	result := SnapshotResult{
		ApplicationID: common.HexToHash("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
		SourceTee:     common.HexToAddress("0x1111111111111111111111111111111111111111"),
		RecoveryTee:   common.HexToAddress("0x2222222222222222222222222222222222222222"),
		Nonce:         7,
		Epoch:         8,
		ParentRoot:    common.HexToHash("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
		StateRoot:     common.HexToHash("0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
		Ciphertext:    []byte{1, 2, 3},
	}
	encoded, err := encodeSnapshotResult(result)
	if err != nil {
		t.Fatal(err)
	}
	want := common.FromHex("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000000000000000000001111111111111111111111111111111111111111000000000000000000000000222222222222222222222222222222222222222200000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000008bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000030102030000000000000000000000000000000000000000000000000000000000")
	if !bytes.Equal(encoded, want) {
		t.Fatalf("Go and Solidity tuple encodings differ\ngot  %x\nwant %x", encoded, want)
	}
}

func TestSnapshotRejectsReplayWrongParentAndWrongRecoveryKey(t *testing.T) {
	primaryKey := mustKey(t)
	recoveryKey := mustKey(t)
	wrongKey := mustKey(t)
	primary := New(testApplicationID, crypto.PubkeyToAddress(primaryKey.PublicKey), keyDecrypter{primaryKey})
	entry, _ := utils.Encrypt([]byte("one"), &primaryKey.PublicKey)
	base := snapshotRequest{
		ApplicationID:  testApplicationID,
		Nonce:          1,
		Epoch:          1,
		ParentRoot:     primary.State().StateRoot,
		RecoveryTee:    crypto.PubkeyToAddress(recoveryKey.PublicKey),
		PublicKeyX:     common.BytesToHash(recoveryKey.PublicKey.X.Bytes()),
		PublicKeyY:     common.BytesToHash(recoveryKey.PublicKey.Y.Bytes()),
		EncryptedEntry: entry,
	}
	if result := postAction(t, primary, snapshotAction(t, base, crypto.PubkeyToAddress(primaryKey.PublicKey))); result.Status != 1 {
		t.Fatal(result.Log)
	}
	if result := postAction(t, primary, snapshotAction(t, base, crypto.PubkeyToAddress(primaryKey.PublicKey))); result.Status != 0 {
		t.Fatal("replayed nonce accepted")
	}

	fresh := New(testApplicationID, crypto.PubkeyToAddress(primaryKey.PublicKey), keyDecrypter{primaryKey})
	wrongParent := base
	wrongParent.ParentRoot = crypto.Keccak256Hash([]byte("fork"))
	if result := postAction(t, fresh, snapshotAction(t, wrongParent, crypto.PubkeyToAddress(primaryKey.PublicKey))); result.Status != 0 {
		t.Fatal("wrong parent accepted")
	}
	wrongRecipient := base
	wrongRecipient.PublicKeyX = common.BytesToHash(wrongKey.PublicKey.X.Bytes())
	wrongRecipient.PublicKeyY = common.BytesToHash(wrongKey.PublicKey.Y.Bytes())
	if result := postAction(t, fresh, snapshotAction(t, wrongRecipient, crypto.PubkeyToAddress(primaryKey.PublicKey))); result.Status != 0 {
		t.Fatal("wrong recovery key accepted")
	}
}

func TestSnapshotFailureDoesNotMutateState(t *testing.T) {
	primaryKey := mustKey(t)
	recoveryKey := mustKey(t)
	beforeExtension := NewWithCrypto(
		testApplicationID,
		crypto.PubkeyToAddress(primaryKey.PublicKey),
		keyDecrypter{primaryKey},
		func([]byte, *ecdsa.PublicKey) ([]byte, error) { return nil, errors.New("entropy unavailable") },
	)
	entry, _ := utils.Encrypt([]byte("one"), &primaryKey.PublicKey)
	request := snapshotRequest{
		ApplicationID:  testApplicationID,
		Nonce:          1,
		Epoch:          1,
		ParentRoot:     beforeExtension.State().StateRoot,
		RecoveryTee:    crypto.PubkeyToAddress(recoveryKey.PublicKey),
		PublicKeyX:     common.BytesToHash(recoveryKey.PublicKey.X.Bytes()),
		PublicKeyY:     common.BytesToHash(recoveryKey.PublicKey.Y.Bytes()),
		EncryptedEntry: entry,
	}
	before := beforeExtension.State()
	result := postAction(t, beforeExtension, snapshotAction(t, request, crypto.PubkeyToAddress(primaryKey.PublicKey)))
	if result.Status != 0 {
		t.Fatal("encryption failure accepted")
	}
	after := beforeExtension.State()
	if after.Epoch != before.Epoch || after.StateRoot != before.StateRoot || len(after.Entries) != 0 {
		t.Fatal("state mutated before encrypted snapshot was ready")
	}
}

func TestSnapshotRejectsOversizedEntryWithoutMutation(t *testing.T) {
	primaryKey := mustKey(t)
	recoveryKey := mustKey(t)
	primary := New(testApplicationID, crypto.PubkeyToAddress(primaryKey.PublicKey), keyDecrypter{primaryKey})
	entry, err := utils.Encrypt(bytes.Repeat([]byte{0x41}, maxEntryBytes+1), &primaryKey.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	request := snapshotRequest{
		ApplicationID: testApplicationID, Nonce: 1, Epoch: 1, ParentRoot: primary.State().StateRoot,
		RecoveryTee: crypto.PubkeyToAddress(recoveryKey.PublicKey),
		PublicKeyX:  common.BytesToHash(recoveryKey.PublicKey.X.Bytes()),
		PublicKeyY:  common.BytesToHash(recoveryKey.PublicKey.Y.Bytes()), EncryptedEntry: entry,
	}
	result := postAction(t, primary, snapshotAction(t, request, crypto.PubkeyToAddress(primaryKey.PublicKey)))
	if result.Status != statusError || primary.State().Epoch != 0 || len(primary.State().Entries) != 0 {
		t.Fatal("oversized entry was accepted or mutated state")
	}
}

func TestDecodeSnapshotRejectsNonCanonicalMetadataAndEntries(t *testing.T) {
	tests := []struct {
		name        string
		schema      common.Hash
		epoch       uint64
		nextEntryID uint64
		nextNonce   uint64
		ids         []uint64
		plaintexts  [][]byte
	}{
		{name: "wrong schema", schema: common.HexToHash("0x01"), epoch: 1, nextEntryID: 2, nextNonce: 2, ids: []uint64{1}, plaintexts: [][]byte{[]byte("one")}},
		{name: "empty", schema: StateVersion, epoch: 0, nextEntryID: 1, nextNonce: 1},
		{name: "epoch count", schema: StateVersion, epoch: 2, nextEntryID: 2, nextNonce: 3, ids: []uint64{1}, plaintexts: [][]byte{[]byte("one")}},
		{name: "next entry", schema: StateVersion, epoch: 1, nextEntryID: 3, nextNonce: 2, ids: []uint64{1}, plaintexts: [][]byte{[]byte("one")}},
		{name: "next nonce", schema: StateVersion, epoch: 1, nextEntryID: 2, nextNonce: 3, ids: []uint64{1}, plaintexts: [][]byte{[]byte("one")}},
		{name: "first id", schema: StateVersion, epoch: 1, nextEntryID: 2, nextNonce: 2, ids: []uint64{2}, plaintexts: [][]byte{[]byte("one")}},
		{name: "oversized entry", schema: StateVersion, epoch: 1, nextEntryID: 2, nextNonce: 2, ids: []uint64{1}, plaintexts: [][]byte{bytes.Repeat([]byte{0x41}, maxEntryBytes+1)}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			encoded, err := snapshotArguments().Pack(
				testApplicationID, test.schema, test.epoch, common.HexToHash("0x01"), test.nextEntryID,
				test.nextNonce, test.ids, test.plaintexts,
			)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := decodeSnapshot(encoded); err == nil {
				t.Fatal("non-canonical snapshot accepted")
			}
		})
	}
}

func TestRestoreRejectsStaleTamperedWrongKeyAndInvalidRoot(t *testing.T) {
	primaryKey := mustKey(t)
	recoveryKey := mustKey(t)
	otherKey := mustKey(t)
	primary := New(testApplicationID, crypto.PubkeyToAddress(primaryKey.PublicKey), keyDecrypter{primaryKey})
	result := createSnapshot(t, primary, primaryKey, recoveryKey)
	decoded := decodeSnapshotResult(t, result.Data)
	base := restoreRequest{
		ApplicationID:    testApplicationID,
		Epoch:            1,
		StateRoot:        decoded.StateRoot,
		CiphertextDigest: crypto.Keccak256Hash(decoded.Ciphertext),
		Ciphertext:       decoded.Ciphertext,
	}

	tampered := base
	tampered.Ciphertext = append([]byte(nil), base.Ciphertext...)
	tampered.Ciphertext[0] ^= 0xff
	if result := postAction(t, New(testApplicationID, crypto.PubkeyToAddress(recoveryKey.PublicKey), keyDecrypter{recoveryKey}), restoreAction(t, tampered, crypto.PubkeyToAddress(recoveryKey.PublicKey))); result.Status != 0 {
		t.Fatal("tampered ciphertext accepted")
	}
	if result := postAction(t, New(testApplicationID, crypto.PubkeyToAddress(otherKey.PublicKey), keyDecrypter{otherKey}), restoreAction(t, base, crypto.PubkeyToAddress(otherKey.PublicKey))); result.Status != 0 {
		t.Fatal("ciphertext encrypted for another TEE accepted")
	}
	wrongRoot := base
	wrongRoot.StateRoot = crypto.Keccak256Hash([]byte("wrong"))
	if result := postAction(t, New(testApplicationID, crypto.PubkeyToAddress(recoveryKey.PublicKey), keyDecrypter{recoveryKey}), restoreAction(t, wrongRoot, crypto.PubkeyToAddress(recoveryKey.PublicKey))); result.Status != 0 {
		t.Fatal("wrong claimed root accepted")
	}

	recovery := New(testApplicationID, crypto.PubkeyToAddress(recoveryKey.PublicKey), keyDecrypter{recoveryKey})
	if result := postAction(t, recovery, restoreAction(t, base, crypto.PubkeyToAddress(recoveryKey.PublicKey))); result.Status != 1 {
		t.Fatal(result.Log)
	}
	stale := base
	stale.Epoch = 0
	if result := postAction(t, recovery, restoreAction(t, stale, crypto.PubkeyToAddress(recoveryKey.PublicKey))); result.Status != 0 {
		t.Fatal("stale restore accepted")
	}
}

func TestRestoreRejectsCompetingRootAtCurrentEpoch(t *testing.T) {
	key := mustKey(t)
	extension := New(testApplicationID, crypto.PubkeyToAddress(key.PublicKey), keyDecrypter{key})
	request := restoreRequest{
		ApplicationID:    testApplicationID,
		Epoch:            0,
		StateRoot:        crypto.Keccak256Hash([]byte("competing-genesis")),
		CiphertextDigest: crypto.Keccak256Hash([]byte("irrelevant")),
		Ciphertext:       []byte("irrelevant"),
	}
	result := postAction(t, extension, restoreAction(t, request, crypto.PubkeyToAddress(key.PublicKey)))
	if result.Status != statusError {
		t.Fatal("competing current-epoch root accepted")
	}
}

func TestMalformedActionIsHTTP400AndUnknownCommandIsSignedError(t *testing.T) {
	key := mustKey(t)
	extension := New(testApplicationID, crypto.PubkeyToAddress(key.PublicKey), keyDecrypter{key})
	recorder := httptest.NewRecorder()
	extension.Handler().ServeHTTP(recorder, httptest.NewRequest(http.MethodPost, "/action", bytes.NewBufferString("{} {}")))
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("malformed action status %d", recorder.Code)
	}

	action := actionWithMessage(t, common.HexToHash("0x01"), crypto.PubkeyToAddress(key.PublicKey), OpType, common.HexToHash("0x99"), nil)
	result := postAction(t, extension, action)
	if result.Status != 0 || result.OPType != OpType || result.OPCommand != common.HexToHash("0x99") {
		t.Fatal("unknown command did not return an echoed signed error")
	}
}

func createSnapshot(t *testing.T, extension *Extension, primaryKey, recoveryKey *ecdsa.PrivateKey) types.ActionResult {
	t.Helper()
	entry, err := utils.Encrypt([]byte("private"), &primaryKey.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	request := snapshotRequest{
		ApplicationID:  testApplicationID,
		Nonce:          1,
		Epoch:          1,
		ParentRoot:     extension.State().StateRoot,
		RecoveryTee:    crypto.PubkeyToAddress(recoveryKey.PublicKey),
		PublicKeyX:     common.BytesToHash(recoveryKey.PublicKey.X.Bytes()),
		PublicKeyY:     common.BytesToHash(recoveryKey.PublicKey.Y.Bytes()),
		EncryptedEntry: entry,
	}
	return postAction(t, extension, snapshotAction(t, request, crypto.PubkeyToAddress(primaryKey.PublicKey)))
}

func snapshotAction(t *testing.T, request snapshotRequest, teeID common.Address) types.Action {
	t.Helper()
	message, err := snapshotRequestArguments().Pack(
		request.ApplicationID, request.Nonce, request.Epoch, request.ParentRoot, request.RecoveryTee,
		request.PublicKeyX, request.PublicKeyY, request.EncryptedEntry,
	)
	if err != nil {
		t.Fatal(err)
	}
	return actionWithMessage(t, crypto.Keccak256Hash([]byte("snapshot-action")), teeID, OpType, OpSnapshot, message)
}

func restoreAction(t *testing.T, request restoreRequest, teeID common.Address) types.Action {
	t.Helper()
	message, err := restoreRequestArguments().Pack(
		request.ApplicationID, request.Epoch, request.StateRoot, request.CiphertextDigest, request.Ciphertext,
	)
	if err != nil {
		t.Fatal(err)
	}
	return actionWithMessage(t, crypto.Keccak256Hash([]byte("restore-action")), teeID, OpType, OpRestore, message)
}

func actionWithMessage(t *testing.T, id common.Hash, teeID common.Address, opType, command common.Hash, original []byte) types.Action {
	t.Helper()
	fixed := instruction.DataFixed{InstructionID: id, TeeID: teeID, OPType: opType, OPCommand: command, OriginalMessage: original}
	encoded, err := json.Marshal(fixed)
	if err != nil {
		t.Fatal(err)
	}
	return types.Action{Data: types.ActionData{ID: id, SubmissionTag: types.Submit, Message: encoded}}
}

func postAction(t *testing.T, extension *Extension, action types.Action) types.ActionResult {
	t.Helper()
	body, err := json.Marshal(action)
	if err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	extension.Handler().ServeHTTP(recorder, httptest.NewRequest(http.MethodPost, "/action", bytes.NewReader(body)))
	if recorder.Code != http.StatusOK {
		t.Fatalf("action HTTP status %d: %s", recorder.Code, recorder.Body.String())
	}
	var result types.ActionResult
	if err := json.Unmarshal(recorder.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func decodeSnapshotResult(t *testing.T, data []byte) SnapshotResult {
	t.Helper()
	values, err := snapshotResultArguments().Unpack(data)
	if err != nil {
		t.Fatal(err)
	}
	return SnapshotResult{
		ApplicationID: values[0].([32]byte), SourceTee: values[1].(common.Address), RecoveryTee: values[2].(common.Address),
		Nonce: values[3].(uint64), Epoch: values[4].(uint64), ParentRoot: values[5].([32]byte),
		StateRoot: values[6].([32]byte), Ciphertext: values[7].([]byte),
	}
}

func decodeRecoveryResult(t *testing.T, data []byte) RecoveryResult {
	t.Helper()
	values, err := recoveryResultArguments().Unpack(data)
	if err != nil {
		t.Fatal(err)
	}
	return RecoveryResult{
		ApplicationID: values[0].([32]byte), RecoveryTee: values[1].(common.Address), Epoch: values[2].(uint64),
		StateRoot: values[3].([32]byte), CiphertextDigest: values[4].([32]byte),
	}
}

func assertEcho(t *testing.T, result types.ActionResult, action types.Action, opType, command common.Hash) {
	t.Helper()
	if result.ID != action.Data.ID || result.SubmissionTag != action.Data.SubmissionTag || result.OPType != opType || result.OPCommand != command {
		t.Fatal("ActionResult did not echo FCC action identity")
	}
}

func mustKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	key, err := crypto.GenerateKey()
	if err != nil {
		t.Fatal(err)
	}
	return key
}
