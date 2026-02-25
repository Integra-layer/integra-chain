package integra

import (
	"github.com/cosmos/evm/crypto/hd"
	evmtypes "github.com/cosmos/evm/x/vm/types"

	clienthelpers "cosmossdk.io/client/v2/helpers"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

const (
	// Bech32Prefix defines the Bech32 prefix for Integra Layer addresses.
	Bech32Prefix = "integra"
	// Bech32PrefixAccAddr defines the Bech32 prefix of an account's address.
	Bech32PrefixAccAddr = Bech32Prefix
	// Bech32PrefixAccPub defines the Bech32 prefix of an account's public key.
	Bech32PrefixAccPub = Bech32Prefix + sdk.PrefixPublic
	// Bech32PrefixValAddr defines the Bech32 prefix of a validator's operator address.
	Bech32PrefixValAddr = Bech32Prefix + sdk.PrefixValidator + sdk.PrefixOperator
	// Bech32PrefixValPub defines the Bech32 prefix of a validator's operator public key.
	Bech32PrefixValPub = Bech32Prefix + sdk.PrefixValidator + sdk.PrefixOperator + sdk.PrefixPublic
	// Bech32PrefixConsAddr defines the Bech32 prefix of a consensus node address.
	Bech32PrefixConsAddr = Bech32Prefix + sdk.PrefixValidator + sdk.PrefixConsensus
	// Bech32PrefixConsPub defines the Bech32 prefix of a consensus node public key.
	Bech32PrefixConsPub = Bech32Prefix + sdk.PrefixValidator + sdk.PrefixConsensus + sdk.PrefixPublic

	// IntegraEVMChainID is the EIP-155 chain ID for Integra Layer mainnet.
	IntegraEVMChainID = 26217
	// IntegraTestnetEVMChainID is the EIP-155 chain ID for Integra Layer testnet.
	IntegraTestnetEVMChainID = 26218

	// IntegraChainDenom is the base denomination (smallest unit) of IRL.
	IntegraChainDenom = "airl"
	// IntegraDisplayDenom is the display denomination of IRL.
	IntegraDisplayDenom = "irl"

	// AppName is the application name used in CLI.
	AppName = "intgd"
	// AppNodeHome is the default node home directory name.
	AppNodeHome = ".intgd"
)

// IntegraChainsCoinInfo maps Integra chain IDs to their coin info.
var IntegraChainsCoinInfo = map[uint64]evmtypes.EvmCoinInfo{
	IntegraEVMChainID: {
		Denom:         IntegraChainDenom,
		ExtendedDenom: IntegraChainDenom,
		DisplayDenom:  IntegraDisplayDenom,
		Decimals:      evmtypes.EighteenDecimals.Uint32(),
	},
	IntegraTestnetEVMChainID: {
		Denom:         IntegraChainDenom,
		ExtendedDenom: IntegraChainDenom,
		DisplayDenom:  IntegraDisplayDenom,
		Decimals:      evmtypes.EighteenDecimals.Uint32(),
	},
}

// MustGetDefaultNodeHome returns the default node home directory for intgd.
func MustGetDefaultNodeHome() string {
	defaultNodeHome, err := clienthelpers.GetNodeHomeDirectory(AppNodeHome)
	if err != nil {
		panic(err)
	}
	return defaultNodeHome
}

// SetBech32Prefixes sets the global Bech32 prefixes for Integra Layer addresses.
func SetBech32Prefixes(config *sdk.Config) {
	config.SetBech32PrefixForAccount(Bech32PrefixAccAddr, Bech32PrefixAccPub)
	config.SetBech32PrefixForValidator(Bech32PrefixValAddr, Bech32PrefixValPub)
	config.SetBech32PrefixForConsensusNode(Bech32PrefixConsAddr, Bech32PrefixConsPub)
}

// SetBip44CoinType sets the global coin type for HD wallets.
func SetBip44CoinType(config *sdk.Config) {
	config.SetCoinType(hd.Bip44CoinType)
	config.SetPurpose(sdk.Purpose)
	config.SetFullFundraiserPath(hd.BIP44HDPath) //nolint: staticcheck
}
