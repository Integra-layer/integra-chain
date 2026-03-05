package eips_test

import (
	"testing"

	"github.com/Integra-layer/integra-chain/integra/tests/integration"

	"github.com/cosmos/evm/tests/integration/eips"
)

func TestEIPs(t *testing.T) {
	eips.RunTests(t, integration.CreateEvmd)
}
