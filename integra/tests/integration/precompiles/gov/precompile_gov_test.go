package gov

import (
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/Integra-layer/integra-chain/integra/tests/integration"
	"github.com/cosmos/evm/tests/integration/precompiles/gov"
)

func TestGovPrecompileTestSuite(t *testing.T) {
	s := gov.NewPrecompileTestSuite(integration.CreateEvmd)
	suite.Run(t, s)
}

func TestGovPrecompileIntegrationTestSuite(t *testing.T) {
	gov.TestPrecompileIntegrationTestSuite(t, integration.CreateEvmd)
}
