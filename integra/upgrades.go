package integra

import (
	"context"

	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	"github.com/cosmos/evm/x/vm/types"

	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"

	storetypes "cosmossdk.io/store/types"
	upgradetypes "cosmossdk.io/x/upgrade/types"
)

// UpgradeName defines the on-chain upgrade name.
const UpgradeName = "v0.4.0-to-v0.5.0"

func (app IntegraApp) RegisterUpgradeHandlers() {
	app.UpgradeKeeper.SetUpgradeHandler(
		UpgradeName,
		func(ctx context.Context, _ upgradetypes.Plan, fromVM module.VersionMap) (module.VersionMap, error) {
			sdkCtx := sdk.UnwrapSDKContext(ctx)
			sdkCtx.Logger().Debug("running upgrade handler")

			app.BankKeeper.SetDenomMetaData(ctx, banktypes.Metadata{
				Description: "Integra Layer Native Token",
				DenomUnits: []*banktypes.DenomUnit{
					{
						Denom:    "airl",
						Exponent: 0,
						Aliases:  nil,
					},
					{
						Denom:    "irl",
						Exponent: 18,
						Aliases:  nil,
					},
				},
				Base:    "airl",
				Display: "irl",
				Name:    "IRL",
				Symbol:  "IRL",
			})

			evmParams := app.EVMKeeper.GetParams(sdkCtx)
			evmParams.ExtendedDenomOptions = &types.ExtendedDenomOptions{ExtendedDenom: "airl"}
			err := app.EVMKeeper.SetParams(sdkCtx, evmParams)
			if err != nil {
				return nil, err
			}
			// Initialize EvmCoinInfo in the module store
			if err := app.EVMKeeper.InitEvmCoinInfo(sdkCtx); err != nil {
				return nil, err
			}
			return app.ModuleManager.RunMigrations(ctx, app.Configurator(), fromVM)
		},
	)

	upgradeInfo, err := app.UpgradeKeeper.ReadUpgradeInfoFromDisk()
	if err != nil {
		panic(err)
	}

	if upgradeInfo.Name == UpgradeName && !app.UpgradeKeeper.IsSkipHeight(upgradeInfo.Height) {
		storeUpgrades := storetypes.StoreUpgrades{
			Added: []string{},
		}
		// configure store loader that checks if version == upgradeHeight and applies store upgrades
		app.SetStoreLoader(upgradetypes.UpgradeStoreLoader(upgradeInfo.Height, &storeUpgrades))
	}
}
