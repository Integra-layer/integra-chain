package cmd

import (
	"encoding/json"
	"fmt"

	integra "github.com/Integra-layer/integra-chain/integra"
	"github.com/cosmos/cosmos-sdk/types/module"
	genutilcli "github.com/cosmos/cosmos-sdk/x/genutil/client/cli"
	genutiltypes "github.com/cosmos/cosmos-sdk/x/genutil/types"
	"github.com/spf13/cobra"
)

// CustomInitCmd wraps the SDK InitCmd and applies Integra-specific genesis
// parameter overrides (inflation, fee market, staking, governance, etc.)
// after the standard init completes.
func CustomInitCmd(app *integra.IntegraApp, mbm module.BasicManager, defaultNodeHome string) *cobra.Command {
	initCmd := genutilcli.InitCmd(mbm, defaultNodeHome)

	// Wrap the original RunE to apply our genesis overrides after init
	origRunE := initCmd.RunE
	initCmd.RunE = func(cmd *cobra.Command, args []string) error {
		// Run the standard SDK init first
		if err := origRunE(cmd, args); err != nil {
			return err
		}

		// Now overwrite the genesis with our custom defaults
		home, _ := cmd.Flags().GetString("home")
		if home == "" {
			home = defaultNodeHome
		}
		genFile := fmt.Sprintf("%s/config/genesis.json", home)

		appGenesis, err := genutiltypes.AppGenesisFromFile(genFile)
		if err != nil {
			return fmt.Errorf("failed to read genesis file: %w", err)
		}

		// Get our custom genesis state (with Integra overrides)
		customGenState := app.DefaultGenesis()

		// Marshal and replace the app state
		appState, err := json.MarshalIndent(customGenState, "", " ")
		if err != nil {
			return fmt.Errorf("failed to marshal custom genesis state: %w", err)
		}
		appGenesis.AppState = appState

		// Write the updated genesis file
		genDoc, err := appGenesis.ToGenesisDoc()
		if err != nil {
			return fmt.Errorf("failed to convert to genesis doc: %w", err)
		}
		if err := genDoc.SaveAs(genFile); err != nil {
			return fmt.Errorf("failed to save genesis file: %w", err)
		}

		return nil
	}

	return initCmd
}
