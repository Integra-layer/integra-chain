package integra

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

func TestBech32Prefixes(t *testing.T) {
	require.Equal(t, "integra", Bech32Prefix)
	require.Equal(t, "integra", Bech32PrefixAccAddr)
	require.Equal(t, "integrapub", Bech32PrefixAccPub)
	require.Equal(t, "integravaloper", Bech32PrefixValAddr)
	require.True(t, strings.HasPrefix(Bech32PrefixValAddr, "integra"))
	require.True(t, strings.HasPrefix(Bech32PrefixValPub, "integra"))
	require.True(t, strings.HasPrefix(Bech32PrefixConsAddr, "integra"))
	require.True(t, strings.HasPrefix(Bech32PrefixConsPub, "integra"))
}

func TestChainConstants(t *testing.T) {
	require.EqualValues(t, 26217, IntegraEVMChainID)
	require.EqualValues(t, 26218, IntegraTestnetEVMChainID)
	require.Equal(t, "airl", IntegraChainDenom)
	require.Equal(t, "irl", IntegraDisplayDenom)
	require.Equal(t, "intgd", AppName)
	require.Equal(t, ".intgd", AppNodeHome)
}

func TestChainsCoinInfo(t *testing.T) {
	// Mainnet coin info
	mainnet, ok := IntegraChainsCoinInfo[IntegraEVMChainID]
	require.True(t, ok, "mainnet chain ID should be in ChainsCoinInfo")
	require.Equal(t, "airl", mainnet.Denom)
	require.Equal(t, "airl", mainnet.ExtendedDenom)
	require.Equal(t, "irl", mainnet.DisplayDenom)
	require.Equal(t, uint32(18), mainnet.Decimals)

	// Testnet coin info
	testnet, ok := IntegraChainsCoinInfo[IntegraTestnetEVMChainID]
	require.True(t, ok, "testnet chain ID should be in ChainsCoinInfo")
	require.Equal(t, "airl", testnet.Denom)
	require.Equal(t, uint32(18), testnet.Decimals)
}

func TestMustGetDefaultNodeHome(t *testing.T) {
	home := MustGetDefaultNodeHome()
	require.NotEmpty(t, home)
	require.True(t, strings.HasSuffix(home, ".intgd"), "home dir should end with .intgd, got: %s", home)
}

func TestSetBech32Prefixes(t *testing.T) {
	config := sdk.GetConfig()
	SetBech32Prefixes(config)

	require.Equal(t, "integra", config.GetBech32AccountAddrPrefix())
	require.Equal(t, "integrapub", config.GetBech32AccountPubPrefix())
	require.Equal(t, "integravaloper", config.GetBech32ValidatorAddrPrefix())
	require.Equal(t, "integravaloperpub", config.GetBech32ValidatorPubPrefix())
	require.Equal(t, "integravalcons", config.GetBech32ConsensusAddrPrefix())
	require.Equal(t, "integravalconspub", config.GetBech32ConsensusPubPrefix())
}
