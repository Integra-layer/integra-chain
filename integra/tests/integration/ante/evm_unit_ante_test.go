package ante

import (
	"testing"

	"github.com/Integra-layer/integra-chain/integra/tests/integration"
	"github.com/stretchr/testify/suite"

	"github.com/cosmos/evm/tests/integration/ante"
)

func TestEvmUnitAnteTestSuite(t *testing.T) {
	suite.Run(t, ante.NewEvmUnitAnteTestSuite(integration.CreateEvmd))
}
