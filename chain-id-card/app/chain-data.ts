export type Network = "mainnet" | "testnet";

export interface ChainSpec {
  identity: {
    name: string;
    binary: string;
    bech32Prefix: string;
    homeDir: string;
    cosmosSDK: string;
    evmFramework: string;
    cometBFT: string;
  };
  network: {
    chainId: string;
    evmChainId: number;
    status: string;
  };
  token: {
    name: string;
    symbol: string;
    baseDenom: string;
    displayDenom: string;
    decimals: number;
    totalSupply: string;
  };
  mint: {
    inflation: string;
    inflationMin: string;
    inflationMax: string;
    inflationRateChange: string;
    goalBonded: string;
    blocksPerYear: number;
    blockTime: string;
  };
  feeMarket: {
    eip1559Enabled: boolean;
    baseFee: string;
    baseFeeGwei: string;
    minGasPrice: string;
    baseFeeChangeDenominator: number;
    elasticityMultiplier: number;
    minGasMultiplier: string;
  };
  staking: {
    bondDenom: string;
    maxValidators: number;
    unbondingPeriod: string;
    maxEntries: number;
    historicalEntries: number;
    minCommissionRate: string;
  };
  governance: {
    minDeposit: string;
    minDepositDisplay: string;
    expeditedMinDeposit: string;
    expeditedMinDepositDisplay: string;
    maxDepositPeriod: string;
    votingPeriod: string;
    expeditedVotingPeriod: string;
    quorum: string;
    threshold: string;
    vetoThreshold: string;
    minInitialDepositRatio: string;
    burnVoteVeto: boolean;
  };
  slashing: {
    signedBlocksWindow: number;
    minSignedPerWindow: string;
    downtimeJailDuration: string;
    slashFractionDoubleSign: string;
    slashFractionDowntime: string;
  };
  distribution: {
    communityTax: string;
    withdrawAddrEnabled: boolean;
  };
  precompiles: {
    name: string;
    address: string;
    description: string;
  }[];
  predeployed: {
    name: string;
    address: string;
    description: string;
  }[];
  modules: string[];
  endpoints: {
    rpc: string;
    rest: string;
    grpc: string;
    evmRpc: string;
    evmWs: string;
    explorer: string;
    evmExplorer: string;
  };
}

const sharedSpec = {
  identity: {
    name: "Integra Layer",
    binary: "intgd",
    bech32Prefix: "integra",
    homeDir: "~/.intgd",
    cosmosSDK: "v0.50.x",
    evmFramework: "cosmos/evm v0.5.1",
    cometBFT: "v0.38.x",
  },
  token: {
    name: "IRL",
    symbol: "IRL",
    baseDenom: "airl",
    displayDenom: "IRL",
    decimals: 18,
    totalSupply: "100,000,000,000 IRL",
  },
  mint: {
    inflation: "1%",
    inflationMin: "1%",
    inflationMax: "1%",
    inflationRateChange: "0%",
    goalBonded: "0%",
    blocksPerYear: 6_311_520,
    blockTime: "~5 seconds",
  },
  feeMarket: {
    eip1559Enabled: true,
    baseFee: "5,000,000,000,000 airl",
    baseFeeGwei: "5,000 gwei",
    minGasPrice: "5,000,000,000,000 airl",
    baseFeeChangeDenominator: 8,
    elasticityMultiplier: 2,
    minGasMultiplier: "0.5",
  },
  staking: {
    bondDenom: "airl",
    maxValidators: 100,
    unbondingPeriod: "21 days",
    maxEntries: 7,
    historicalEntries: 10_000,
    minCommissionRate: "0%",
  },
  governance: {
    minDeposit: "1,000,000,000,000,000,000,000,000 airl",
    minDepositDisplay: "1,000,000 IRL",
    expeditedMinDeposit: "5,000,000,000,000,000,000,000,000 airl",
    expeditedMinDepositDisplay: "5,000,000 IRL",
    maxDepositPeriod: "7 days",
    votingPeriod: "5 days",
    expeditedVotingPeriod: "1 day",
    quorum: "33.4%",
    threshold: "50%",
    vetoThreshold: "33.4%",
    minInitialDepositRatio: "25%",
    burnVoteVeto: true,
  },
  slashing: {
    signedBlocksWindow: 10_000,
    minSignedPerWindow: "5%",
    downtimeJailDuration: "10 minutes",
    slashFractionDoubleSign: "5%",
    slashFractionDowntime: "0.01%",
  },
  distribution: {
    communityTax: "0%",
    withdrawAddrEnabled: true,
  },
  precompiles: [
    { name: "P256 Verifier", address: "0x0000000000000000000000000000000000000100", description: "ECDSA signature verification on the P-256 (secp256r1) curve" },
    { name: "Bech32", address: "0x0000000000000000000000000000000000000400", description: "Convert between Bech32 and hex address formats" },
    { name: "Staking", address: "0x0000000000000000000000000000000000000800", description: "Delegate, undelegate, redelegate, and query validators from EVM" },
    { name: "Distribution", address: "0x0000000000000000000000000000000000000801", description: "Claim staking rewards and manage distribution params from EVM" },
    { name: "ICS-20 Transfer", address: "0x0000000000000000000000000000000000000802", description: "IBC token transfers directly from EVM smart contracts" },
    { name: "Vesting", address: "0x0000000000000000000000000000000000000803", description: "Create and manage vesting accounts from EVM" },
    { name: "Bank", address: "0x0000000000000000000000000000000000000804", description: "Query balances, send tokens, and manage supplies from EVM" },
    { name: "Governance", address: "0x0000000000000000000000000000000000000805", description: "Submit proposals and vote from EVM smart contracts" },
    { name: "Slashing", address: "0x0000000000000000000000000000000000000806", description: "Query slashing params and validator signing info from EVM" },
  ],
  predeployed: [
    { name: "WIRL (Wrapped IRL)", address: "0xD4949664cD82660AaE99bEdc034a0deA8A0bd517", description: "ERC-20 wrapped version of the native IRL token" },
  ],
  modules: [
    "auth", "authz", "bank", "capability", "consensus",
    "distribution", "evidence", "feegrant", "genutil", "gov",
    "mint", "params", "slashing", "staking", "upgrade",
    "evm", "erc20", "feemarket",
    "ibc-core", "ibc-transfer",
  ],
};

export const chainSpecs: Record<Network, ChainSpec> = {
  mainnet: {
    ...sharedSpec,
    network: {
      chainId: "integra_26217-1",
      evmChainId: 26217,
      status: "Live",
    },
    endpoints: {
      rpc: "https://rpc.integralayer.com",
      rest: "https://rest.integralayer.com",
      grpc: "grpc.integralayer.com:9090",
      evmRpc: "https://evm-rpc.integralayer.com",
      evmWs: "wss://evm-ws.integralayer.com",
      explorer: "https://scan.integralayer.com",
      evmExplorer: "https://blockscout.integralayer.com",
    },
  },
  testnet: {
    ...sharedSpec,
    network: {
      chainId: "integra_26218-1",
      evmChainId: 26218,
      status: "Live",
    },
    endpoints: {
      rpc: "https://ormos.integralayer.com/cometbft",
      rest: "https://ormos.integralayer.com/rest",
      grpc: "ormos.integralayer.com:9090",
      evmRpc: "https://ormos.integralayer.com/rpc",
      evmWs: "wss://ormos.integralayer.com/ws",
      explorer: "https://scan.integralayer.com?network=testnet",
      evmExplorer: "https://testnet.blockscout.integralayer.com",
    },
  },
};
