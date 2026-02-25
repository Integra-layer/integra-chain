package ante

import (
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/Integra-layer/integra-chain/integra/tests/integration"
	"github.com/cosmos/evm/tests/integration/ante"
)

func TestEvmUnitAnteTestSuite(t *testing.T) {
	suite.Run(t, ante.NewEvmUnitAnteTestSuite(integration.CreateEvmd))
}
