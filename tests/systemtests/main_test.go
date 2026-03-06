//go:build system_test

package systemtests

import (
	"testing"

	"cosmossdk.io/systemtests"
)

func TestMain(m *testing.M) {
	systemtests.RunTests(m)
}

// TODO: System tests need to be fully ported from upstream cosmos/evm.
// The following test suites are not yet implemented:
// - mempool (RunTxsOrdering, RunTxsReplacement, etc.)
// - eip712 (RunEIP712BankSend, etc.)
// - accountabstraction (RunEIP7702)
// - chainupgrade (RunChainUpgrade)
//
// The suite package needs BaseTestSuite and RunWithSharedSuite to be implemented.
// Skipping all system tests until the port is complete.
func TestCosmosTxCompat(t *testing.T) {
	t.Skip("system tests not yet ported from upstream cosmos/evm")
}
