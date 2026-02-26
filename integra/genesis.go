package integra

import (
	"encoding/json"
	"math/big"
	"time"

	"cosmossdk.io/math"

	sdk "github.com/cosmos/cosmos-sdk/types"
	distrtypes "github.com/cosmos/cosmos-sdk/x/distribution/types"
	govv1 "github.com/cosmos/cosmos-sdk/x/gov/types/v1"
	minttypes "github.com/cosmos/cosmos-sdk/x/mint/types"
	slashingtypes "github.com/cosmos/cosmos-sdk/x/slashing/types"
	stakingtypes "github.com/cosmos/cosmos-sdk/x/staking/types"

	testconstants "github.com/cosmos/evm/testutil/constants"
	erc20types "github.com/cosmos/evm/x/erc20/types"
	feemarkettypes "github.com/cosmos/evm/x/feemarket/types"
	evmtypes "github.com/cosmos/evm/x/vm/types"
)

// GenesisState of the blockchain is represented here as a map of raw json
// messages key'd by an identifier string.
type GenesisState map[string]json.RawMessage

// NewEVMGenesisState returns the default genesis state for the EVM module.
func NewEVMGenesisState() *evmtypes.GenesisState {
	evmGenState := evmtypes.DefaultGenesisState()
	evmGenState.Params.EvmDenom = IntegraChainDenom
	evmGenState.Params.ActiveStaticPrecompiles = evmtypes.AvailableStaticPrecompiles
	evmGenState.Preinstalls = evmtypes.DefaultPreinstalls

	return evmGenState
}

// NewErc20GenesisState returns the default genesis state for the ERC20 module.
func NewErc20GenesisState() *erc20types.GenesisState {
	erc20GenState := erc20types.DefaultGenesisState()
	erc20GenState.TokenPairs = testconstants.ExampleTokenPairs
	erc20GenState.NativePrecompiles = []string{testconstants.WEVMOSContractMainnet}

	return erc20GenState
}

// NewMintGenesisState returns the genesis state for the mint module.
// 1% fixed inflation, 6,311,520 blocks/year (5s block time).
func NewMintGenesisState() *minttypes.GenesisState {
	mintGenState := minttypes.DefaultGenesisState()
	mintGenState.Params.MintDenom = IntegraChainDenom
	mintGenState.Params.InflationRateChange = math.LegacyMustNewDecFromStr("0.0")
	mintGenState.Params.InflationMax = math.LegacyMustNewDecFromStr("0.01")
	mintGenState.Params.InflationMin = math.LegacyMustNewDecFromStr("0.01")
	mintGenState.Params.GoalBonded = math.LegacyMustNewDecFromStr("0.0")
	mintGenState.Params.BlocksPerYear = 6_311_520
	mintGenState.Minter.Inflation = math.LegacyMustNewDecFromStr("0.01")

	return mintGenState
}

// NewFeeMarketGenesisState returns the genesis state for the feemarket module.
// EIP-1559 enabled with 5000 gwei base fee.
func NewFeeMarketGenesisState() *feemarkettypes.GenesisState {
	feeMarketGenState := feemarkettypes.DefaultGenesisState()
	feeMarketGenState.Params.NoBaseFee = false
	feeMarketGenState.Params.BaseFeeChangeDenominator = 8
	feeMarketGenState.Params.ElasticityMultiplier = 2
	feeMarketGenState.Params.BaseFee = math.LegacyNewDec(5_000_000_000_000) // 5000 gwei
	feeMarketGenState.Params.MinGasPrice = math.LegacyMustNewDecFromStr("5000000000000")
	feeMarketGenState.Params.MinGasMultiplier = math.LegacyMustNewDecFromStr("0.5")

	return feeMarketGenState
}

// NewStakingGenesisState returns the genesis state for the staking module.
// 100 max validators, 21-day unbonding, 0% min commission.
func NewStakingGenesisState() *stakingtypes.GenesisState {
	stakingGenState := stakingtypes.DefaultGenesisState()
	stakingGenState.Params.BondDenom = IntegraChainDenom
	stakingGenState.Params.UnbondingTime = 21 * 24 * time.Hour
	stakingGenState.Params.MaxValidators = 100
	stakingGenState.Params.MaxEntries = 7
	stakingGenState.Params.HistoricalEntries = 10000
	stakingGenState.Params.MinCommissionRate = math.LegacyMustNewDecFromStr("0.0")

	return stakingGenState
}

// NewGovGenesisState returns the genesis state for the governance module.
// 1M IRL min deposit, 5-day voting, 1-day expedited.
func NewGovGenesisState() *govv1.GenesisState {
	govGenState := govv1.DefaultGenesisState()

	// 1,000,000 IRL = 1e24 airl
	minDeposit, _ := new(big.Int).SetString("1000000000000000000000000", 10)
	govGenState.Params.MinDeposit = sdk.NewCoins(sdk.NewCoin(IntegraChainDenom, math.NewIntFromBigInt(minDeposit)))

	// 5,000,000 IRL = 5e24 airl
	expeditedMinDeposit, _ := new(big.Int).SetString("5000000000000000000000000", 10)
	govGenState.Params.ExpeditedMinDeposit = sdk.NewCoins(sdk.NewCoin(IntegraChainDenom, math.NewIntFromBigInt(expeditedMinDeposit)))

	maxDepositPeriod := 7 * 24 * time.Hour
	govGenState.Params.MaxDepositPeriod = &maxDepositPeriod

	votingPeriod := 5 * 24 * time.Hour
	govGenState.Params.VotingPeriod = &votingPeriod

	expeditedVotingPeriod := 24 * time.Hour
	govGenState.Params.ExpeditedVotingPeriod = &expeditedVotingPeriod

	govGenState.Params.Quorum = "0.334"
	govGenState.Params.Threshold = "0.5"
	govGenState.Params.VetoThreshold = "0.334"
	govGenState.Params.MinInitialDepositRatio = "0.25"
	govGenState.Params.BurnVoteVeto = true

	return govGenState
}

// NewSlashingGenesisState returns the genesis state for the slashing module.
// Cosmos Hub standard parameters.
func NewSlashingGenesisState() *slashingtypes.GenesisState {
	slashingGenState := slashingtypes.DefaultGenesisState()
	slashingGenState.Params.SignedBlocksWindow = 10000
	slashingGenState.Params.MinSignedPerWindow = math.LegacyMustNewDecFromStr("0.05")
	slashingGenState.Params.DowntimeJailDuration = 10 * time.Minute
	slashingGenState.Params.SlashFractionDoubleSign = math.LegacyMustNewDecFromStr("0.05")
	slashingGenState.Params.SlashFractionDowntime = math.LegacyMustNewDecFromStr("0.0001")

	return slashingGenState
}

// NewDistributionGenesisState returns the genesis state for the distribution module.
// 0% community tax.
func NewDistributionGenesisState() *distrtypes.GenesisState {
	distrGenState := distrtypes.DefaultGenesisState()
	distrGenState.Params.CommunityTax = math.LegacyMustNewDecFromStr("0.0")
	distrGenState.Params.WithdrawAddrEnabled = true

	return distrGenState
}
