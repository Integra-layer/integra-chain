package integra

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"cosmossdk.io/math"
)

func TestNewMintGenesisState(t *testing.T) {
	state := NewMintGenesisState()
	require.NotNil(t, state)

	params := state.Params
	require.Equal(t, "airl", params.MintDenom)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.01"), params.InflationMax)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.01"), params.InflationMin)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), params.InflationRateChange)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), params.GoalBonded)
	require.Equal(t, uint64(6_311_520), params.BlocksPerYear)

	// Minter should start at 1% inflation
	require.Equal(t, math.LegacyMustNewDecFromStr("0.01"), state.Minter.Inflation)
}

func TestNewFeeMarketGenesisState(t *testing.T) {
	state := NewFeeMarketGenesisState()
	require.NotNil(t, state)

	params := state.Params
	require.False(t, params.NoBaseFee, "base fee should be enabled")
	require.Equal(t, uint32(8), params.BaseFeeChangeDenominator)
	require.Equal(t, uint32(2), params.ElasticityMultiplier)
	require.Equal(t, math.LegacyNewDec(5_000_000_000_000), params.BaseFee)
	require.Equal(t, math.LegacyMustNewDecFromStr("5000000000000"), params.MinGasPrice)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.5"), params.MinGasMultiplier)
}

func TestNewStakingGenesisState(t *testing.T) {
	state := NewStakingGenesisState()
	require.NotNil(t, state)

	params := state.Params
	require.Equal(t, "airl", params.BondDenom)
	require.Equal(t, 21*24*time.Hour, params.UnbondingTime)
	require.Equal(t, uint32(100), params.MaxValidators)
	require.Equal(t, uint32(7), params.MaxEntries)
	require.Equal(t, uint32(10000), params.HistoricalEntries)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), params.MinCommissionRate)
}

func TestNewGovGenesisState(t *testing.T) {
	state := NewGovGenesisState()
	require.NotNil(t, state)

	params := state.Params
	// Min deposit: 1,000,000 IRL = 1e24 airl
	require.Len(t, params.MinDeposit, 1)
	require.Equal(t, "airl", params.MinDeposit[0].Denom)
	require.Equal(t, "1000000000000000000000000", params.MinDeposit[0].Amount.String())

	// Expedited min deposit: 5,000,000 IRL = 5e24 airl
	require.Len(t, params.ExpeditedMinDeposit, 1)
	require.Equal(t, "5000000000000000000000000", params.ExpeditedMinDeposit[0].Amount.String())

	require.Equal(t, 7*24*time.Hour, *params.MaxDepositPeriod)
	require.Equal(t, 5*24*time.Hour, *params.VotingPeriod)
	require.Equal(t, 24*time.Hour, *params.ExpeditedVotingPeriod)

	require.Equal(t, "0.334", params.Quorum)
	require.Equal(t, "0.5", params.Threshold)
	require.Equal(t, "0.334", params.VetoThreshold)
	require.Equal(t, "0.25", params.MinInitialDepositRatio)
	require.True(t, params.BurnVoteVeto)
}

func TestNewSlashingGenesisState(t *testing.T) {
	state := NewSlashingGenesisState()
	require.NotNil(t, state)

	params := state.Params
	require.Equal(t, int64(10000), params.SignedBlocksWindow)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.05"), params.MinSignedPerWindow)
	require.Equal(t, 10*time.Minute, params.DowntimeJailDuration)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.05"), params.SlashFractionDoubleSign)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0001"), params.SlashFractionDowntime)
}

func TestNewDistributionGenesisState(t *testing.T) {
	state := NewDistributionGenesisState()
	require.NotNil(t, state)

	params := state.Params
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), params.CommunityTax)
	require.True(t, params.WithdrawAddrEnabled)
}

func TestNewEVMGenesisState(t *testing.T) {
	state := NewEVMGenesisState()
	require.NotNil(t, state)
	require.NotEmpty(t, state.Params.ActiveStaticPrecompiles)
	require.NotEmpty(t, state.Preinstalls)
}

func TestNewErc20GenesisState(t *testing.T) {
	state := NewErc20GenesisState()
	require.NotNil(t, state)
	require.NotEmpty(t, state.TokenPairs)
	require.NotEmpty(t, state.NativePrecompiles)
}
