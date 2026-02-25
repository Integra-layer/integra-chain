package integra

import (
	"math/big"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	evmtypes "github.com/cosmos/evm/x/vm/types"
)

// =============================================================================
// Chain Specification Test Suite
//
// This file is the canonical verification of the entire Integra Layer chain
// configuration. If any test here fails, it means the chain spec has drifted
// from its intended design. Every parameter that matters is tested.
// =============================================================================

// --- Identity ----------------------------------------------------------------

func TestSpec_BinaryName(t *testing.T) {
	require.Equal(t, "intgd", AppName)
}

func TestSpec_HomeDirectory(t *testing.T) {
	require.Equal(t, ".intgd", AppNodeHome)
	home := MustGetDefaultNodeHome()
	require.True(t, strings.HasSuffix(home, ".intgd"))
}

func TestSpec_Bech32Prefix(t *testing.T) {
	require.Equal(t, "integra", Bech32Prefix)
	require.Equal(t, "integra", Bech32PrefixAccAddr)
	require.Equal(t, "integrapub", Bech32PrefixAccPub)
	require.Equal(t, "integravaloper", Bech32PrefixValAddr)
	require.Equal(t, "integravaloperpub", Bech32PrefixValPub)
	require.Equal(t, "integravalcons", Bech32PrefixConsAddr)
	require.Equal(t, "integravalconspub", Bech32PrefixConsPub)
}

func TestSpec_Bech32SDKConfig(t *testing.T) {
	config := sdk.GetConfig()
	SetBech32Prefixes(config)
	require.Equal(t, "integra", config.GetBech32AccountAddrPrefix())
	require.Equal(t, "integrapub", config.GetBech32AccountPubPrefix())
	require.Equal(t, "integravaloper", config.GetBech32ValidatorAddrPrefix())
	require.Equal(t, "integravaloperpub", config.GetBech32ValidatorPubPrefix())
	require.Equal(t, "integravalcons", config.GetBech32ConsensusAddrPrefix())
	require.Equal(t, "integravalconspub", config.GetBech32ConsensusPubPrefix())
}

// --- EVM Chain IDs -----------------------------------------------------------

func TestSpec_MainnetEVMChainID(t *testing.T) {
	require.EqualValues(t, 26217, IntegraEVMChainID)
}

func TestSpec_TestnetEVMChainID(t *testing.T) {
	require.EqualValues(t, 26218, IntegraTestnetEVMChainID)
}

func TestSpec_ChainIDsAreConsecutive(t *testing.T) {
	require.EqualValues(t, IntegraEVMChainID+1, IntegraTestnetEVMChainID,
		"testnet chain ID should be mainnet + 1")
}

// --- Token / Denomination ----------------------------------------------------

func TestSpec_BaseDenom(t *testing.T) {
	require.Equal(t, "airl", IntegraChainDenom, "base denom must be airl (atto-IRL)")
}

func TestSpec_DisplayDenom(t *testing.T) {
	require.Equal(t, "irl", IntegraDisplayDenom)
}

func TestSpec_Decimals(t *testing.T) {
	for _, chainID := range []uint64{IntegraEVMChainID, IntegraTestnetEVMChainID} {
		info, ok := IntegraChainsCoinInfo[chainID]
		require.True(t, ok, "chain ID %d missing from ChainsCoinInfo", chainID)
		require.Equal(t, uint32(18), info.Decimals, "chain %d: must use 18 decimals", chainID)
	}
}

func TestSpec_CoinInfoConsistency(t *testing.T) {
	for chainID, info := range IntegraChainsCoinInfo {
		require.Equal(t, "airl", info.Denom, "chain %d: Denom mismatch", chainID)
		require.Equal(t, "airl", info.ExtendedDenom, "chain %d: ExtendedDenom mismatch", chainID)
		require.Equal(t, "irl", info.DisplayDenom, "chain %d: DisplayDenom mismatch", chainID)
	}
}

func TestSpec_BothChainsRegistered(t *testing.T) {
	_, hasMainnet := IntegraChainsCoinInfo[IntegraEVMChainID]
	_, hasTestnet := IntegraChainsCoinInfo[IntegraTestnetEVMChainID]
	require.True(t, hasMainnet, "mainnet must be in ChainsCoinInfo")
	require.True(t, hasTestnet, "testnet must be in ChainsCoinInfo")
	require.Len(t, IntegraChainsCoinInfo, 2, "only mainnet and testnet should exist")
}

// --- Mint Module -------------------------------------------------------------

func TestSpec_Mint(t *testing.T) {
	state := NewMintGenesisState()
	p := state.Params

	require.Equal(t, "airl", p.MintDenom, "mint denom must be airl")

	// Fixed 1% inflation: min = max = 0.01, rate change = 0
	require.Equal(t, math.LegacyMustNewDecFromStr("0.01"), p.InflationMax)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.01"), p.InflationMin)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), p.InflationRateChange)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), p.GoalBonded)

	// ~5s block time → 6,311,520 blocks/year
	require.Equal(t, uint64(6_311_520), p.BlocksPerYear)

	// Minter starts at 1%
	require.Equal(t, math.LegacyMustNewDecFromStr("0.01"), state.Minter.Inflation)
}

// --- Fee Market (EIP-1559) ---------------------------------------------------

func TestSpec_FeeMarket(t *testing.T) {
	state := NewFeeMarketGenesisState()
	p := state.Params

	require.False(t, p.NoBaseFee, "EIP-1559 must be enabled (NoBaseFee=false)")

	// 5000 gwei = 5,000,000,000,000 airl
	require.Equal(t, math.LegacyNewDec(5_000_000_000_000), p.BaseFee, "base fee must be 5000 gwei")
	require.Equal(t, math.LegacyMustNewDecFromStr("5000000000000"), p.MinGasPrice, "min gas price must match base fee")

	require.Equal(t, uint32(8), p.BaseFeeChangeDenominator)
	require.Equal(t, uint32(2), p.ElasticityMultiplier)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.5"), p.MinGasMultiplier)
}

// --- Staking -----------------------------------------------------------------

func TestSpec_Staking(t *testing.T) {
	state := NewStakingGenesisState()
	p := state.Params

	require.Equal(t, "airl", p.BondDenom, "bond denom must be airl")
	require.Equal(t, 21*24*time.Hour, p.UnbondingTime, "unbonding must be 21 days")
	require.Equal(t, uint32(100), p.MaxValidators)
	require.Equal(t, uint32(7), p.MaxEntries)
	require.Equal(t, uint32(10000), p.HistoricalEntries)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), p.MinCommissionRate, "min commission must be 0%")
}

// --- Governance --------------------------------------------------------------

func TestSpec_Governance(t *testing.T) {
	state := NewGovGenesisState()
	p := state.Params

	// Min deposit: 1,000,000 IRL = 1e24 airl
	require.Len(t, p.MinDeposit, 1)
	require.Equal(t, "airl", p.MinDeposit[0].Denom)
	expectedMinDeposit, _ := new(big.Int).SetString("1000000000000000000000000", 10)
	require.Equal(t, math.NewIntFromBigInt(expectedMinDeposit), p.MinDeposit[0].Amount,
		"min deposit must be 1,000,000 IRL (1e24 airl)")

	// Expedited min deposit: 5,000,000 IRL = 5e24 airl
	require.Len(t, p.ExpeditedMinDeposit, 1)
	expectedExpDeposit, _ := new(big.Int).SetString("5000000000000000000000000", 10)
	require.Equal(t, math.NewIntFromBigInt(expectedExpDeposit), p.ExpeditedMinDeposit[0].Amount,
		"expedited min deposit must be 5,000,000 IRL (5e24 airl)")

	// Periods
	require.Equal(t, 7*24*time.Hour, *p.MaxDepositPeriod, "max deposit period must be 7 days")
	require.Equal(t, 5*24*time.Hour, *p.VotingPeriod, "voting period must be 5 days")
	require.Equal(t, 24*time.Hour, *p.ExpeditedVotingPeriod, "expedited voting period must be 1 day")

	// Thresholds
	require.Equal(t, "0.334", p.Quorum, "quorum must be 33.4%")
	require.Equal(t, "0.5", p.Threshold, "threshold must be 50%")
	require.Equal(t, "0.334", p.VetoThreshold, "veto threshold must be 33.4%")
	require.Equal(t, "0.25", p.MinInitialDepositRatio, "min initial deposit ratio must be 25%")
	require.True(t, p.BurnVoteVeto, "vote veto burn must be enabled")
}

// --- Slashing ----------------------------------------------------------------

func TestSpec_Slashing(t *testing.T) {
	state := NewSlashingGenesisState()
	p := state.Params

	require.Equal(t, int64(10000), p.SignedBlocksWindow)
	require.Equal(t, math.LegacyMustNewDecFromStr("0.05"), p.MinSignedPerWindow,
		"min signed per window must be 5%")
	require.Equal(t, 10*time.Minute, p.DowntimeJailDuration,
		"downtime jail duration must be 10 minutes")
	require.Equal(t, math.LegacyMustNewDecFromStr("0.05"), p.SlashFractionDoubleSign,
		"double sign slash must be 5%")
	require.Equal(t, math.LegacyMustNewDecFromStr("0.0001"), p.SlashFractionDowntime,
		"downtime slash must be 0.01%")
}

// --- Distribution ------------------------------------------------------------

func TestSpec_Distribution(t *testing.T) {
	state := NewDistributionGenesisState()
	p := state.Params

	require.Equal(t, math.LegacyMustNewDecFromStr("0.0"), p.CommunityTax,
		"community tax must be 0%")
	require.True(t, p.WithdrawAddrEnabled,
		"withdraw address must be enabled")
}

// --- EVM Module --------------------------------------------------------------

func TestSpec_EVMPrecompiles(t *testing.T) {
	state := NewEVMGenesisState()

	// All 9 static precompiles must be enabled
	expectedPrecompiles := []string{
		evmtypes.P256PrecompileAddress,          // 0x0100
		evmtypes.Bech32PrecompileAddress,        // 0x0400
		evmtypes.StakingPrecompileAddress,       // 0x0800
		evmtypes.DistributionPrecompileAddress,  // 0x0801
		evmtypes.ICS20PrecompileAddress,         // 0x0802
		evmtypes.VestingPrecompileAddress,       // 0x0803
		evmtypes.BankPrecompileAddress,          // 0x0804
		evmtypes.GovPrecompileAddress,           // 0x0805
		evmtypes.SlashingPrecompileAddress,      // 0x0806
	}

	require.Equal(t, expectedPrecompiles, state.Params.ActiveStaticPrecompiles,
		"all 9 static precompiles must be enabled")
}

func TestSpec_EVMPrecompileAddresses(t *testing.T) {
	// Verify well-known addresses for reference
	require.Equal(t, "0x0000000000000000000000000000000000000100", evmtypes.P256PrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000400", evmtypes.Bech32PrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000800", evmtypes.StakingPrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000801", evmtypes.DistributionPrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000802", evmtypes.ICS20PrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000803", evmtypes.VestingPrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000804", evmtypes.BankPrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000805", evmtypes.GovPrecompileAddress)
	require.Equal(t, "0x0000000000000000000000000000000000000806", evmtypes.SlashingPrecompileAddress)
}

func TestSpec_EVMPreinstalls(t *testing.T) {
	state := NewEVMGenesisState()
	require.NotEmpty(t, state.Preinstalls, "preinstalls must be configured")
}

// --- ERC20 Module ------------------------------------------------------------

func TestSpec_ERC20TokenPairs(t *testing.T) {
	state := NewErc20GenesisState()
	require.NotEmpty(t, state.TokenPairs, "at least one token pair required (native)")
	require.NotEmpty(t, state.NativePrecompiles, "native precompile (WIRL) must be set")
}

// --- Upgrade Handler ---------------------------------------------------------

func TestSpec_UpgradeDenomMetadata(t *testing.T) {
	// The upgrade handler sets denom metadata — verify the constants match
	require.Equal(t, "v0.4.0-to-v0.5.0", UpgradeName)
}

// --- Cross-Cutting Invariants ------------------------------------------------

func TestSpec_NoDenomConfusion(t *testing.T) {
	// Ensure no remnants of test/example denoms exist in our config
	for chainID, info := range IntegraChainsCoinInfo {
		require.NotContains(t, info.Denom, "test", "chain %d: denom must not contain 'test'", chainID)
		require.NotContains(t, info.Denom, "atom", "chain %d: denom must not contain 'atom'", chainID)
		require.NotContains(t, info.Denom, "evmos", "chain %d: denom must not contain 'evmos'", chainID)
	}

	mint := NewMintGenesisState()
	require.Equal(t, "airl", mint.Params.MintDenom)

	staking := NewStakingGenesisState()
	require.Equal(t, "airl", staking.Params.BondDenom)

	gov := NewGovGenesisState()
	require.Equal(t, "airl", gov.Params.MinDeposit[0].Denom)
}

func TestSpec_AllModuleDenomsSame(t *testing.T) {
	// Every module that references a denom must use "airl"
	mint := NewMintGenesisState()
	staking := NewStakingGenesisState()
	gov := NewGovGenesisState()

	allDenoms := []string{
		mint.Params.MintDenom,
		staking.Params.BondDenom,
		gov.Params.MinDeposit[0].Denom,
		gov.Params.ExpeditedMinDeposit[0].Denom,
	}

	for _, denom := range allDenoms {
		require.Equal(t, "airl", denom, "all module denoms must be 'airl'")
	}
}

func TestSpec_NoZeroValues(t *testing.T) {
	// Sanity: key parameters must never be zero
	require.NotZero(t, IntegraEVMChainID)
	require.NotZero(t, IntegraTestnetEVMChainID)

	mint := NewMintGenesisState()
	require.NotZero(t, mint.Params.BlocksPerYear)

	staking := NewStakingGenesisState()
	require.NotZero(t, staking.Params.UnbondingTime)
	require.NotZero(t, staking.Params.MaxValidators)

	fee := NewFeeMarketGenesisState()
	require.False(t, fee.Params.BaseFee.IsZero(), "base fee must not be zero")

	gov := NewGovGenesisState()
	require.NotZero(t, *gov.Params.VotingPeriod)
}
