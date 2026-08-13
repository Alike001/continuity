package journal

import (
	"bytes"
	"crypto/ecdsa"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"sync"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/flare-foundation/go-flare-common/pkg/tee/instruction"
	"github.com/flare-foundation/tee-node/pkg/types"
	teeutils "github.com/flare-foundation/tee-node/pkg/utils"
)

var (
	StateVersion = teeutils.ToHash("CONTINUITY_STATE_V1")
	OpType       = teeutils.ToHash("CONTINUITY")
	OpSnapshot   = teeutils.ToHash("SNAPSHOT")
	OpRestore    = teeutils.ToHash("RESTORE")
)

const (
	statusError       = uint8(0)
	statusSuccess     = uint8(1)
	maxBodyBytes      = 1 << 20
	maxEntryBytes     = 4 << 10
	maxJournalEntries = 64
	maxSnapshotBytes  = 256 << 10
)

type Entry struct {
	ID        uint64
	Plaintext []byte
}

type State struct {
	ApplicationID common.Hash
	Epoch         uint64
	StateRoot     common.Hash
	NextEntryID   uint64
	NextNonce     uint64
	Entries       []Entry
}

type Snapshot struct {
	ApplicationID common.Hash
	Epoch         uint64
	StateRoot     common.Hash
	NextEntryID   uint64
	NextNonce     uint64
	Entries       []Entry
}

type SnapshotResult struct {
	ApplicationID common.Hash
	SourceTee     common.Address
	RecoveryTee   common.Address
	Nonce         uint64
	Epoch         uint64
	ParentRoot    common.Hash
	StateRoot     common.Hash
	Ciphertext    []byte
}

type RecoveryResult struct {
	ApplicationID    common.Hash
	RecoveryTee      common.Address
	Epoch            uint64
	StateRoot        common.Hash
	CiphertextDigest common.Hash
}

type Decrypter interface {
	Decrypt(ciphertext []byte) ([]byte, error)
}

type Encryptor func(plaintext []byte, publicKey *ecdsa.PublicKey) ([]byte, error)

type Extension struct {
	mu        sync.RWMutex
	teeID     common.Address
	state     State
	decryptor Decrypter
	encrypt   Encryptor
}

type stateResponse struct {
	StateVersion common.Hash   `json:"stateVersion"`
	State        hexutil.Bytes `json:"state"`
}

func New(applicationID common.Hash, teeID common.Address, decryptor Decrypter) *Extension {
	return NewWithCrypto(applicationID, teeID, decryptor, teeutils.Encrypt)
}

func NewWithCrypto(applicationID common.Hash, teeID common.Address, decryptor Decrypter, encrypt Encryptor) *Extension {
	state := State{
		ApplicationID: applicationID,
		StateRoot: crypto.Keccak256Hash(
			mustPack(arguments("bytes32", "bytes32"), applicationID, teeutils.ToHash("CONTINUITY_GENESIS")),
		),
		NextEntryID: 1,
		NextNonce:   1,
	}
	return &Extension{teeID: teeID, state: state, decryptor: decryptor, encrypt: encrypt}
}

func (e *Extension) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /state", e.stateHandler)
	mux.HandleFunc("POST /action", e.actionHandler)
	return mux
}

func (e *Extension) State() State {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return cloneState(e.state)
}

func Root(state State) common.Hash {
	entryHashes := make([]common.Hash, len(state.Entries))
	for i, entry := range state.Entries {
		entryHashes[i] = crypto.Keccak256Hash(
			common.LeftPadBytes(newUint(entry.ID).Bytes(), 32),
			crypto.Keccak256(entry.Plaintext),
		)
	}
	return crypto.Keccak256Hash(
		state.ApplicationID[:],
		common.LeftPadBytes(newUint(state.Epoch).Bytes(), 32),
		common.LeftPadBytes(newUint(state.NextEntryID).Bytes(), 32),
		common.LeftPadBytes(newUint(state.NextNonce).Bytes(), 32),
		flattenHashes(entryHashes),
	)
}

func (e *Extension) stateHandler(w http.ResponseWriter, _ *http.Request) {
	e.mu.RLock()
	state := encodeAttestedState(e.state.ApplicationID, e.state.Epoch, e.state.StateRoot)
	e.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(stateResponse{StateVersion: StateVersion, State: state}); err != nil {
		http.Error(w, fmt.Sprintf("encoding state: %v", err), http.StatusInternalServerError)
	}
}

func (e *Extension) actionHandler(w http.ResponseWriter, r *http.Request) {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	decoder.DisallowUnknownFields()
	var action types.Action
	if err := decoder.Decode(&action); err != nil {
		http.Error(w, fmt.Sprintf("decoding action: %v", err), http.StatusBadRequest)
		return
	}
	if err := requireEOF(decoder); err != nil {
		http.Error(w, fmt.Sprintf("decoding action: %v", err), http.StatusBadRequest)
		return
	}

	result := e.process(action)
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(result); err != nil {
		http.Error(w, fmt.Sprintf("encoding result: %v", err), http.StatusInternalServerError)
	}
}

func (e *Extension) process(action types.Action) types.ActionResult {
	fixed, err := decodeFixedMessage(action.Data.Message)
	if err != nil {
		return buildResult(action, common.Hash{}, common.Hash{}, nil, statusError, err)
	}
	if fixed.InstructionID != action.Data.ID || fixed.TeeID != e.teeID {
		return buildResult(
			action, fixed.OPType, fixed.OPCommand, nil, statusError, errors.New("instruction identity mismatch"),
		)
	}
	if fixed.OPType != OpType {
		return buildResult(
			action, fixed.OPType, fixed.OPCommand, nil, statusError, errors.New("unsupported operation type"),
		)
	}

	switch fixed.OPCommand {
	case OpSnapshot:
		return e.snapshot(action, fixed.OriginalMessage)
	case OpRestore:
		return e.restore(action, fixed.OriginalMessage)
	default:
		return buildResult(
			action, fixed.OPType, fixed.OPCommand, nil, statusError, errors.New("unsupported operation command"),
		)
	}
}

func (e *Extension) snapshot(action types.Action, message []byte) types.ActionResult {
	request, err := decodeSnapshotRequest(message)
	if err != nil {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, fmt.Errorf("decoding snapshot request: %w", err))
	}
	current := e.State()
	if request.ApplicationID != current.ApplicationID || request.Nonce != current.NextNonce {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("application or nonce mismatch"))
	}
	if request.Epoch != current.Epoch+1 || request.ParentRoot != current.StateRoot {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("epoch or parent mismatch"))
	}
	if request.RecoveryTee == (common.Address{}) || request.RecoveryTee == e.teeID || len(request.EncryptedEntry) == 0 {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("invalid recovery target or entry"))
	}

	publicKey, err := publicKey(request.PublicKeyX, request.PublicKeyY)
	if err != nil || crypto.PubkeyToAddress(*publicKey) != request.RecoveryTee {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("recovery public key mismatch"))
	}
	plaintext, err := e.decryptor.Decrypt(request.EncryptedEntry)
	if err != nil || len(plaintext) == 0 || len(plaintext) > maxEntryBytes {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("entry decryption failed"))
	}

	e.mu.Lock()
	defer e.mu.Unlock()
	if request.Nonce != e.state.NextNonce || request.Epoch != e.state.Epoch+1 || request.ParentRoot != e.state.StateRoot {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("state changed during request"))
	}
	if len(e.state.Entries) >= maxJournalEntries {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("journal entry limit reached"))
	}

	next := cloneState(e.state)
	next.Entries = append(next.Entries, Entry{ID: next.NextEntryID, Plaintext: append([]byte(nil), plaintext...)})
	next.NextEntryID++
	next.NextNonce++
	next.Epoch = request.Epoch
	next.StateRoot = Root(next)
	snapshotBytes, err := encodeSnapshot(next)
	if err != nil {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, fmt.Errorf("encoding snapshot: %w", err))
	}
	if len(snapshotBytes) > maxSnapshotBytes {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, errors.New("encoded snapshot exceeds size limit"))
	}
	ciphertext, err := e.encrypt(snapshotBytes, publicKey)
	if err != nil {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, fmt.Errorf("encrypting snapshot: %w", err))
	}
	resultData, err := encodeSnapshotResult(SnapshotResult{
		ApplicationID: next.ApplicationID,
		SourceTee:     e.teeID,
		RecoveryTee:   request.RecoveryTee,
		Nonce:         request.Nonce,
		Epoch:         next.Epoch,
		ParentRoot:    request.ParentRoot,
		StateRoot:     next.StateRoot,
		Ciphertext:    ciphertext,
	})
	if err != nil {
		return buildResult(action, OpType, OpSnapshot, nil, statusError, fmt.Errorf("encoding result: %w", err))
	}
	e.state = next
	return buildResult(action, OpType, OpSnapshot, resultData, statusSuccess, nil)
}

func (e *Extension) restore(action types.Action, message []byte) types.ActionResult {
	request, err := decodeRestoreRequest(message)
	if err != nil {
		return buildResult(action, OpType, OpRestore, nil, statusError, fmt.Errorf("decoding restore request: %w", err))
	}
	current := e.State()
	if request.ApplicationID != current.ApplicationID || request.Epoch < current.Epoch {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("stale or foreign snapshot"))
	}
	if request.Epoch == current.Epoch && request.StateRoot != current.StateRoot {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("competing snapshot at current epoch"))
	}
	if len(request.Ciphertext) == 0 || crypto.Keccak256Hash(request.Ciphertext) != request.CiphertextDigest {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("ciphertext digest mismatch"))
	}
	plaintext, err := e.decryptor.Decrypt(request.Ciphertext)
	if err != nil {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("snapshot decryption failed"))
	}
	snapshot, err := decodeSnapshot(plaintext)
	if err != nil {
		return buildResult(action, OpType, OpRestore, nil, statusError, fmt.Errorf("decoding snapshot: %w", err))
	}
	if snapshot.ApplicationID != request.ApplicationID || snapshot.Epoch != request.Epoch || snapshot.StateRoot != request.StateRoot {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("snapshot metadata mismatch"))
	}
	restored := State(snapshot)
	if Root(restored) != snapshot.StateRoot {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("snapshot state root mismatch"))
	}
	resultData, err := encodeRecoveryResult(RecoveryResult{
		ApplicationID:    request.ApplicationID,
		RecoveryTee:      e.teeID,
		Epoch:            request.Epoch,
		StateRoot:        request.StateRoot,
		CiphertextDigest: request.CiphertextDigest,
	})
	if err != nil {
		return buildResult(action, OpType, OpRestore, nil, statusError, fmt.Errorf("encoding result: %w", err))
	}

	e.mu.Lock()
	defer e.mu.Unlock()
	if request.Epoch < e.state.Epoch {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("state advanced during restore"))
	}
	if request.Epoch == e.state.Epoch && request.StateRoot != e.state.StateRoot {
		return buildResult(action, OpType, OpRestore, nil, statusError, errors.New("state forked during restore"))
	}
	e.state = cloneState(restored)
	return buildResult(action, OpType, OpRestore, resultData, statusSuccess, nil)
}

func buildResult(action types.Action, opType, opCommand common.Hash, data []byte, status uint8, err error) types.ActionResult {
	result := types.ActionResult{
		ID:            action.Data.ID,
		SubmissionTag: action.Data.SubmissionTag,
		Status:        status,
		OPType:        opType,
		OPCommand:     opCommand,
		Version:       "1.0.0",
		Data:          data,
	}
	if err != nil {
		result.Log = "error: " + err.Error()
	} else {
		result.Log = "ok"
	}
	return result
}

func cloneState(state State) State {
	clone := state
	clone.Entries = make([]Entry, len(state.Entries))
	for i, entry := range state.Entries {
		clone.Entries[i] = Entry{ID: entry.ID, Plaintext: append([]byte(nil), entry.Plaintext...)}
	}
	return clone
}

func requireEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("multiple JSON values")
		}
		return err
	}
	return nil
}

func publicKey(x, y common.Hash) (*ecdsa.PublicKey, error) {
	key := &ecdsa.PublicKey{Curve: crypto.S256(), X: newUintBytes(x[:]), Y: newUintBytes(y[:])}
	if !key.Curve.IsOnCurve(key.X, key.Y) {
		return nil, errors.New("public key is not on secp256k1")
	}
	return key, nil
}

func flattenHashes(hashes []common.Hash) []byte {
	flat := make([]byte, 0, len(hashes)*common.HashLength)
	for _, hash := range hashes {
		flat = append(flat, hash[:]...)
	}
	return flat
}

func newUint(value uint64) *big.Int { return new(big.Int).SetUint64(value) }

func newUintBytes(value []byte) *big.Int { return new(big.Int).SetBytes(value) }

type snapshotRequest struct {
	ApplicationID  common.Hash
	Nonce          uint64
	Epoch          uint64
	ParentRoot     common.Hash
	RecoveryTee    common.Address
	PublicKeyX     common.Hash
	PublicKeyY     common.Hash
	EncryptedEntry []byte
}

type restoreRequest struct {
	ApplicationID    common.Hash
	Epoch            uint64
	StateRoot        common.Hash
	CiphertextDigest common.Hash
	Ciphertext       []byte
}

func decodeFixedMessage(message []byte) (instruction.DataFixed, error) {
	var fixed instruction.DataFixed
	decoder := json.NewDecoder(bytes.NewReader(message))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&fixed); err != nil {
		return instruction.DataFixed{}, err
	}
	if err := requireEOF(decoder); err != nil {
		return instruction.DataFixed{}, err
	}
	return fixed, nil
}

func decodeSnapshotRequest(data []byte) (snapshotRequest, error) {
	values, err := snapshotRequestArguments().Unpack(data)
	if err != nil {
		return snapshotRequest{}, err
	}
	return snapshotRequest{
		ApplicationID:  values[0].([32]byte),
		Nonce:          values[1].(uint64),
		Epoch:          values[2].(uint64),
		ParentRoot:     values[3].([32]byte),
		RecoveryTee:    values[4].(common.Address),
		PublicKeyX:     values[5].([32]byte),
		PublicKeyY:     values[6].([32]byte),
		EncryptedEntry: values[7].([]byte),
	}, nil
}

func decodeRestoreRequest(data []byte) (restoreRequest, error) {
	values, err := restoreRequestArguments().Unpack(data)
	if err != nil {
		return restoreRequest{}, err
	}
	return restoreRequest{
		ApplicationID:    values[0].([32]byte),
		Epoch:            values[1].(uint64),
		StateRoot:        values[2].([32]byte),
		CiphertextDigest: values[3].([32]byte),
		Ciphertext:       values[4].([]byte),
	}, nil
}

func encodeAttestedState(applicationID common.Hash, epoch uint64, root common.Hash) []byte {
	encoded, err := attestedStateArguments().Pack(applicationID, epoch, root)
	if err != nil {
		panic(err)
	}
	return encoded
}

func encodeSnapshot(state State) ([]byte, error) {
	ids := make([]uint64, len(state.Entries))
	entries := make([][]byte, len(state.Entries))
	for i, entry := range state.Entries {
		ids[i] = entry.ID
		entries[i] = entry.Plaintext
	}
	return snapshotArguments().Pack(
		state.ApplicationID, StateVersion, state.Epoch, state.StateRoot, state.NextEntryID, state.NextNonce, ids, entries,
	)
}

func decodeSnapshot(data []byte) (Snapshot, error) {
	if len(data) == 0 || len(data) > maxSnapshotBytes {
		return Snapshot{}, errors.New("snapshot size is invalid")
	}
	values, err := snapshotArguments().Unpack(data)
	if err != nil {
		return Snapshot{}, err
	}
	if values[1].([32]byte) != StateVersion {
		return Snapshot{}, errors.New("snapshot schema version mismatch")
	}
	ids := values[6].([]uint64)
	plaintexts := values[7].([][]byte)
	if len(ids) != len(plaintexts) {
		return Snapshot{}, errors.New("entry arrays differ in length")
	}
	epoch := values[2].(uint64)
	nextEntryID := values[4].(uint64)
	nextNonce := values[5].(uint64)
	if len(ids) == 0 || len(ids) > maxJournalEntries || epoch != uint64(len(ids)) ||
		nextEntryID != uint64(len(ids))+1 || nextNonce != epoch+1 {
		return Snapshot{}, errors.New("non-canonical journal metadata")
	}
	entries := make([]Entry, len(ids))
	for i := range ids {
		if ids[i] != uint64(i)+1 || len(plaintexts[i]) == 0 || len(plaintexts[i]) > maxEntryBytes {
			return Snapshot{}, errors.New("invalid ordered journal entry")
		}
		entries[i] = Entry{ID: ids[i], Plaintext: plaintexts[i]}
	}
	return Snapshot{
		ApplicationID: values[0].([32]byte),
		Epoch:         epoch,
		StateRoot:     values[3].([32]byte),
		NextEntryID:   nextEntryID,
		NextNonce:     nextNonce,
		Entries:       entries,
	}, nil
}

func encodeSnapshotResult(result SnapshotResult) ([]byte, error) {
	return snapshotResultArguments().Pack(
		result.ApplicationID, result.SourceTee, result.RecoveryTee, result.Nonce, result.Epoch,
		result.ParentRoot, result.StateRoot, result.Ciphertext,
	)
}

func encodeRecoveryResult(result RecoveryResult) ([]byte, error) {
	return recoveryResultArguments().Pack(
		result.ApplicationID, result.RecoveryTee, result.Epoch, result.StateRoot, result.CiphertextDigest,
	)
}

func snapshotRequestArguments() abi.Arguments {
	return arguments("bytes32", "uint64", "uint64", "bytes32", "address", "bytes32", "bytes32", "bytes")
}

func restoreRequestArguments() abi.Arguments {
	return arguments("bytes32", "uint64", "bytes32", "bytes32", "bytes")
}

func attestedStateArguments() abi.Arguments { return arguments("bytes32", "uint64", "bytes32") }

func snapshotArguments() abi.Arguments {
	return arguments("bytes32", "bytes32", "uint64", "bytes32", "uint64", "uint64", "uint64[]", "bytes[]")
}

func snapshotResultArguments() abi.Arguments {
	return arguments("bytes32", "address", "address", "uint64", "uint64", "bytes32", "bytes32", "bytes")
}

func recoveryResultArguments() abi.Arguments {
	return arguments("bytes32", "address", "uint64", "bytes32", "bytes32")
}

func arguments(names ...string) abi.Arguments {
	args := make(abi.Arguments, len(names))
	for i, name := range names {
		typeValue, err := abi.NewType(name, "", nil)
		if err != nil {
			panic(err)
		}
		args[i] = abi.Argument{Type: typeValue}
	}
	return args
}

func mustPack(args abi.Arguments, values ...any) []byte {
	encoded, err := args.Pack(values...)
	if err != nil {
		panic(err)
	}
	return encoded
}
