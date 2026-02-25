package slashing

import (
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/Integra-layer/integra-chain/integra/tests/integration"
	"github.com/cosmos/evm/tests/integration/precompiles/slashing"
)

func TestSlashingPrecompileTestSuite(t *testing.T) {
	s := slashing.NewPrecompileTestSuite(integration.CreateEvmd)
	suite.Run(t, s)
}

func TestStakingPrecompileIntegrationTestSuite(t *testing.T) {
	slashing.TestPrecompileIntegrationTestSuite(t, integration.CreateEvmd)
}
