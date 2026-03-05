"use client";

import { useState, useEffect } from "react";
import { chainSpecs, type Network } from "./chain-data";
import { IntegraLogo } from "./integra-logo";

type Theme = "light" | "dark";

/** Tooltip for technical terms — dotted underline, hover to reveal explanation */
function Tip({ term, children }: { term: string; children: React.ReactNode }) {
  return (
    <span className="tip-wrapper relative inline-flex items-center">
      <span className="border-b border-dotted border-text-muted cursor-help">
        {term}
      </span>
      <span className="tip-bubble absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2 rounded-lg bg-bg-elevated border border-border text-xs text-text-secondary whitespace-normal max-w-[220px] text-center opacity-0 pointer-events-none transition-opacity duration-200 z-50 shadow-lg">
        {children}
      </span>
    </span>
  );
}

/** Explanations for modules, used by module tags */
const moduleDescriptions: Record<string, string> = {
  auth: "Manages user accounts and authentication",
  authz: "Lets accounts grant permissions to others",
  bank: "Handles token transfers and balances",
  consensus: "Manages blockchain consensus settings",
  distribution: "Distributes staking rewards to validators",
  evidence: "Detects and punishes validator misbehavior",
  feegrant: "Lets one account pay fees for another",
  genutil: "Handles initial chain setup (genesis)",
  gov: "On-chain proposals and voting",
  mint: "Creates new tokens via inflation",
  slashing: "Penalizes validators who go offline",
  staking: "Delegate tokens to validators for rewards",
  upgrade: "Manages chain software upgrades",
  vesting: "Locks tokens that unlock over time",
  evm: "Runs Ethereum smart contracts (Solidity)",
  erc20: "Bridges between Cosmos and EVM tokens",
  feemarket: "Dynamic gas pricing (like Ethereum EIP-1559)",
  precisebank: "High-precision token accounting (18 decimals)",
  "ibc-core": "Cross-chain communication protocol",
  "ibc-tm": "Verifies other chains via light clients",
  "ibc-transfer": "Send tokens to other blockchains",
};

function useTheme() {
  const [theme, setTheme] = useState<Theme>("light");
  useEffect(() => {
    const saved = localStorage.getItem("theme") as Theme | null;
    if (saved) setTheme(saved);
  }, []);
  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("theme", theme);
  }, [theme]);
  return [theme, setTheme] as const;
}

function useNetwork() {
  const [network, setNetwork] = useState<Network>("mainnet");
  useEffect(() => {
    document.documentElement.setAttribute("data-network", network);
  }, [network]);
  return [network, setNetwork] as const;
}

function ThemeToggle({
  theme,
  onChange,
}: {
  theme: Theme;
  onChange: (t: Theme) => void;
}) {
  return (
    <button
      onClick={() => onChange(theme === "light" ? "dark" : "light")}
      className="flex items-center justify-center h-9 w-9 rounded-xl border border-border hover:border-border-strong hover:bg-bg-elevated transition-all cursor-pointer"
      title={`Switch to ${theme === "light" ? "dark" : "light"} mode`}
    >
      {theme === "light" ? (
        <svg
          className="h-4 w-4 text-text-muted"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          strokeWidth={2}
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M21.752 15.002A9.718 9.718 0 0118 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 003 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 009.002-5.998z"
          />
        </svg>
      ) : (
        <svg
          className="h-4 w-4 text-text-muted"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          strokeWidth={2}
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M12 3v2.25m6.364.386l-1.591 1.591M21 12h-2.25m-.386 6.364l-1.591-1.591M12 18.75V21m-4.773-4.227l-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0z"
          />
        </svg>
      )}
    </button>
  );
}

function NetworkToggle({
  network,
  onChange,
}: {
  network: Network;
  onChange: (n: Network) => void;
}) {
  return (
    <div className="relative flex items-center rounded-full bg-bg-elevated p-1 border border-border">
      <button
        onClick={() => onChange("mainnet")}
        className={`relative z-10 rounded-full px-5 py-2 text-sm font-medium transition-all duration-300 cursor-pointer ${
          network === "mainnet"
            ? "text-white"
            : "text-text-muted hover:text-text-secondary"
        }`}
      >
        Mainnet
      </button>
      <button
        onClick={() => onChange("testnet")}
        className={`relative z-10 rounded-full px-5 py-2 text-sm font-medium transition-all duration-300 cursor-pointer ${
          network === "testnet"
            ? "text-white"
            : "text-text-muted hover:text-text-secondary"
        }`}
      >
        Testnet
      </button>
      <div
        className="absolute top-1 h-[calc(100%-8px)] rounded-full transition-all duration-300 ease-out gradient-accent-bg"
        style={{
          left: network === "mainnet" ? "4px" : "calc(50%)",
          width: "calc(50% - 4px)",
        }}
      />
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full bg-success/10 px-3 py-1.5 text-sm font-medium text-success">
      <span
        className="h-2 w-2 rounded-full bg-success"
        style={{ animation: "pulse-dot 2s ease-in-out infinite" }}
      />
      {status}
    </span>
  );
}

function Card({
  title,
  children,
  className = "",
}: {
  title: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`card-hover rounded-2xl border border-border bg-bg-card p-6 ${className}`}
    >
      <h3 className="mb-4 text-lg font-semibold text-text-primary">{title}</h3>
      {children}
    </div>
  );
}

function Row({
  label,
  value,
  mono = false,
  tip,
}: {
  label: string;
  value: string | number | boolean;
  mono?: boolean;
  tip?: string;
}) {
  const display =
    typeof value === "boolean" ? (value ? "Yes" : "No") : String(value);
  return (
    <div className="data-row flex items-start justify-between gap-4 py-2.5 border-b border-border last:border-0">
      <span className="text-sm text-text-muted shrink-0">
        {tip ? <Tip term={label}>{tip}</Tip> : label}
      </span>
      <span
        className={`text-sm text-text-primary text-right ${mono ? "font-mono" : "font-medium"}`}
      >
        {display}
      </span>
    </div>
  );
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      onClick={() => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
      className="copy-btn ml-2 text-xs text-text-muted cursor-pointer"
      title="Copy to clipboard"
    >
      {copied ? "Copied!" : "Copy"}
    </button>
  );
}

function AddressRow({
  name,
  address,
  description,
}: {
  name: string;
  address: string;
  description: string;
}) {
  return (
    <div className="data-row py-3 border-b border-border last:border-0">
      <div className="flex items-center justify-between gap-2 mb-1">
        <span className="text-sm font-medium text-text-primary">{name}</span>
        <div className="flex items-center">
          <code className="text-xs font-mono text-accent">
            {address.slice(0, 10)}...{address.slice(-6)}
          </code>
          <CopyButton text={address} />
        </div>
      </div>
      <p className="text-xs text-text-muted">{description}</p>
    </div>
  );
}

function EndpointRow({
  label,
  url,
  tip,
}: {
  label: string;
  url: string;
  tip?: string;
}) {
  return (
    <div className="data-row flex items-center justify-between gap-4 py-2.5 border-b border-border last:border-0">
      <span className="text-sm text-text-muted shrink-0">
        {tip ? <Tip term={label}>{tip}</Tip> : label}
      </span>
      <div className="flex items-center">
        <code className="text-xs font-mono text-info">{url}</code>
        <CopyButton text={url} />
      </div>
    </div>
  );
}

function SectionHeading({
  id,
  title,
  subtitle,
}: {
  id: string;
  title: string;
  subtitle: string;
}) {
  return (
    <div id={id} className="mb-6 scroll-mt-32">
      <h2 className="text-2xl font-bold text-text-primary mb-1">{title}</h2>
      <p className="text-sm text-text-muted">{subtitle}</p>
      <div className="shimmer-line" />
    </div>
  );
}

const sections = [
  { id: "identity", label: "Identity" },
  { id: "token", label: "Token" },
  { id: "consensus", label: "Consensus" },
  { id: "governance", label: "Governance" },
  { id: "evm", label: "EVM" },
  { id: "modules", label: "Modules" },
  { id: "infrastructure", label: "Infra" },
  { id: "endpoints", label: "Endpoints" },
];

export default function Home() {
  const [theme, setTheme] = useTheme();
  const [network, setNetwork] = useNetwork();
  const spec = chainSpecs[network];

  return (
    <div className="min-h-screen">
      {/* Testnet banner */}
      {network === "testnet" && (
        <div className="testnet-banner fixed top-0 left-0 right-0 z-[60]">
          You are viewing the Testnet configuration — not for production use
        </div>
      )}

      {/* Ambient hero glow */}
      <div
        className="fixed inset-0 overflow-hidden pointer-events-none"
        style={{ background: "var(--t-gradient-hero)" }}
      >
        <div
          className="absolute -top-40 left-1/2 -translate-x-1/2 w-[800px] h-[400px] rounded-full blur-[120px]"
          style={{ background: "var(--t-accent-glow)" }}
        />
      </div>

      {/* Navigation */}
      <nav
        className={`gradient-border fixed left-0 right-0 z-50 border-b border-border backdrop-blur-xl ${network === "testnet" ? "top-[30px]" : "top-0"}`}
        style={{ background: "var(--t-nav-bg)" }}
      >
        <div className="mx-auto max-w-6xl flex items-center justify-between px-6 py-3">
          <div className="flex items-center gap-3">
            <IntegraLogo
              variant="mark"
              color={theme === "dark" ? "pink" : "brand"}
              className="h-8 w-8"
            />
            <span className="text-sm font-semibold text-text-primary hidden sm:inline">
              Integra Layer
            </span>
            <span className="text-xs text-text-muted hidden md:inline">
              Chain Specification
            </span>
          </div>
          <div className="flex items-center gap-3">
            <nav className="hidden lg:flex items-center gap-1">
              {sections.map((s) => (
                <a
                  key={s.id}
                  href={`#${s.id}`}
                  className="px-3 py-1.5 text-xs text-text-muted hover:text-text-primary transition-colors rounded-lg hover:bg-bg-elevated"
                >
                  {s.label}
                </a>
              ))}
            </nav>
            <NetworkToggle network={network} onChange={setNetwork} />
            <ThemeToggle theme={theme} onChange={setTheme} />
          </div>
        </div>
      </nav>

      {/* Hero */}
      <header
        className={`relative pb-16 px-6 ${network === "testnet" ? "pt-[142px]" : "pt-28"}`}
      >
        <div className="mx-auto max-w-6xl">
          <div className="flex flex-col items-center text-center mb-12">
            <div className="mb-6 animate-float">
              <div className="logo-ring h-20 w-20 rounded-2xl gradient-accent-bg glow-accent flex items-center justify-center p-4">
                <IntegraLogo
                  variant="mark"
                  color="white"
                  className="h-full w-full"
                />
              </div>
            </div>
            <h1 className="text-4xl sm:text-5xl font-bold mb-3">
              <span className="gradient-accent-text">Integra Layer</span>
            </h1>
            <p className="text-lg text-text-secondary mb-6 max-w-lg">
              EVM-compatible Cosmos SDK blockchain for real-world asset
              tokenization
            </p>
            <div className="flex flex-wrap items-center justify-center gap-3">
              <StatusBadge status={spec.network.status} />
              {network === "testnet" && (
                <span className="testnet-badge">
                  <svg
                    className="h-3 w-3"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth={2.5}
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      d="M9.75 3.104v5.714a2.25 2.25 0 01-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 014.5 0m0 0v5.714a2.25 2.25 0 00.659 1.591L19 14.5M14.25 3.104c.251.023.501.05.75.082M19 14.5l-2.47 2.47a2.25 2.25 0 01-1.591.659H9.061a2.25 2.25 0 01-1.591-.659L5 14.5m14 0V5.846a1.5 1.5 0 00-1.174-1.462A41.66 41.66 0 0012 4c-2.068 0-4.078.18-6.826.384A1.5 1.5 0 004 5.846V14.5"
                    />
                  </svg>
                  Testnet
                </span>
              )}
              <span className="text-sm font-mono text-text-muted">
                {spec.network.chainId}
              </span>
              <span className="text-xs px-2.5 py-1 rounded-full border border-border font-mono text-text-muted">
                EIP-155: {spec.network.evmChainId}
              </span>
            </div>
          </div>

          {/* Quick stats */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-16">
            {[
              {
                label: "EVM Chain ID",
                value: String(spec.network.evmChainId),
                accent: true,
              },
              { label: "Block Time", value: spec.mint.blockTime },
              { label: "Total Supply", value: "100B IRL" },
              { label: "Inflation", value: spec.mint.inflation },
            ].map((stat) => (
              <div
                key={stat.label}
                className="stat-card rounded-xl border border-border bg-bg-card p-4 text-center"
              >
                <div
                  className={`text-2xl font-bold mb-1 ${stat.accent ? "gradient-accent-text" : "text-text-primary"}`}
                >
                  {stat.value}
                </div>
                <div className="text-xs text-text-muted">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>
      </header>

      {/* Content */}
      <main className="relative px-6 pb-24">
        <div className="mx-auto max-w-6xl space-y-16">
          {/* Identity */}
          <section className="animate-fade-in">
            <SectionHeading
              id="identity"
              title="Identity"
              subtitle="Core chain identification and software versions"
            />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Chain Identity">
                <Row label="Name" value={spec.identity.name} />
                <Row
                  label="Binary"
                  value={spec.identity.binary}
                  mono
                  tip="The program you run to operate a node"
                />
                <Row
                  label="Bech32 Prefix"
                  value={spec.identity.bech32Prefix}
                  mono
                  tip="The prefix for all wallet addresses on this chain (e.g. integra1...)"
                />
                <Row
                  label="Home Directory"
                  value={spec.identity.homeDir}
                  mono
                  tip="Where the node stores its data on disk"
                />
                <Row
                  label="Chain ID"
                  value={spec.network.chainId}
                  mono
                  tip="Unique identifier for this blockchain network"
                />
                <Row
                  label="EVM Chain ID"
                  value={spec.network.evmChainId}
                  mono
                  tip="The number wallets like MetaMask use to connect (EIP-155)"
                />
              </Card>
              <Card title="Software Versions">
                <Row
                  label="EVM Framework"
                  value={spec.identity.evmFramework}
                  tip="Enables Ethereum smart contract support on Cosmos"
                />
                <Row
                  label="Cosmos SDK"
                  value={spec.identity.cosmosSDK}
                  tip="The core blockchain framework this chain is built on"
                />
                <Row
                  label="CometBFT"
                  value={spec.identity.cometBFT}
                  tip="The consensus engine that validators use to agree on blocks"
                />
                <Row
                  label="EIP-1559"
                  value={spec.feeMarket.eip1559Enabled}
                  tip="Ethereum-style dynamic gas pricing — fees adjust with demand"
                />
                <Row
                  label="Precompiles"
                  value={`${spec.precompiles.length} static`}
                  tip="Built-in smart contracts for fast, cheap operations"
                />
                <Row
                  label="IBC"
                  value="Enabled (v10)"
                  tip="Inter-Blockchain Communication — send tokens to other chains"
                />
              </Card>
            </div>
          </section>

          {/* Token */}
          <section className="animate-fade-in-delay-1">
            <SectionHeading
              id="token"
              title="Token"
              subtitle="Native token denomination and supply configuration"
            />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Token Info">
                <Row label="Name" value={spec.token.name} />
                <Row
                  label="Symbol"
                  value={spec.token.symbol}
                  tip="Ticker shown on exchanges and wallets"
                />
                <Row
                  label="Base Denom"
                  value={spec.token.baseDenom}
                  mono
                  tip="Smallest unit used internally (like wei for ETH)"
                />
                <Row
                  label="Display Denom"
                  value={spec.token.displayDenom}
                  tip="Human-readable unit (like ETH vs wei)"
                />
                <Row
                  label="Decimals"
                  value={spec.token.decimals}
                  tip="1 IRL = 1,000,000,000,000,000,000 airl (18 zeros)"
                />
                <Row
                  label="Total Supply"
                  value={spec.token.totalSupply}
                  tip="Maximum tokens created at launch"
                />
              </Card>
              <Card title="Denomination Guide">
                <div className="space-y-4">
                  <div className="rounded-xl bg-bg-elevated p-4">
                    <div className="text-xs text-text-muted mb-2">
                      Conversion
                    </div>
                    <div className="text-sm font-mono text-text-primary">
                      1 IRL = 10<sup>18</sup> airl
                    </div>
                    <div className="text-xs text-text-muted mt-1">
                      Similar to ETH / wei relationship
                    </div>
                  </div>
                  <div className="rounded-xl bg-bg-elevated p-4">
                    <div className="text-xs text-text-muted mb-2">Naming</div>
                    <div className="space-y-1">
                      <div className="flex justify-between text-sm">
                        <span className="text-text-muted">Base unit</span>
                        <code className="font-mono text-accent">airl</code>
                      </div>
                      <div className="flex justify-between text-sm">
                        <span className="text-text-muted">Display unit</span>
                        <code className="font-mono text-brand-gold">IRL</code>
                      </div>
                      <div className="flex justify-between text-sm">
                        <span className="text-text-muted">
                          &quot;a&quot; prefix
                        </span>
                        <span className="text-text-secondary">
                          atto (10<sup>-18</sup>)
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </Card>
            </div>
          </section>

          {/* Consensus */}
          <section className="animate-fade-in-delay-2">
            <SectionHeading
              id="consensus"
              title="Consensus & Economics"
              subtitle="Staking, inflation, fee market, slashing, and distribution parameters"
            />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Mint / Inflation">
                <Row
                  label="Inflation"
                  value={spec.mint.inflation}
                  tip="Rate at which new tokens are created yearly"
                />
                <Row
                  label="Min Inflation"
                  value={spec.mint.inflationMin}
                  tip="Lowest the inflation rate can go"
                />
                <Row
                  label="Max Inflation"
                  value={spec.mint.inflationMax}
                  tip="Highest the inflation rate can go"
                />
                <Row
                  label="Rate Change"
                  value={spec.mint.inflationRateChange}
                  tip="How fast inflation adjusts (0% = fixed)"
                />
                <Row
                  label="Goal Bonded"
                  value={spec.mint.goalBonded}
                  tip="Target percentage of tokens staked (0% = no target)"
                />
                <Row
                  label="Blocks / Year"
                  value={spec.mint.blocksPerYear.toLocaleString()}
                  tip="Expected number of blocks produced each year"
                />
                <Row
                  label="Block Time"
                  value={spec.mint.blockTime}
                  tip="Average time between new blocks"
                />
              </Card>
              <Card title="Fee Market (EIP-1559)">
                <Row
                  label="EIP-1559 Enabled"
                  value={spec.feeMarket.eip1559Enabled}
                  tip="Dynamic fee pricing — gas fees go up when busy, down when quiet"
                />
                <Row
                  label="Base Fee"
                  value={spec.feeMarket.baseFeeGwei}
                  tip="Minimum gas price in gwei (burned, not paid to validators)"
                />
                <Row
                  label="Base Fee (airl)"
                  value={spec.feeMarket.baseFee}
                  mono
                  tip="Same base fee expressed in the smallest token unit"
                />
                <Row
                  label="Min Gas Price"
                  value={spec.feeMarket.minGasPrice}
                  mono
                  tip="Absolute minimum fee — transactions below this are rejected"
                />
                <Row
                  label="Change Denominator"
                  value={spec.feeMarket.baseFeeChangeDenominator}
                  tip="Controls how fast the base fee adjusts (higher = slower)"
                />
                <Row
                  label="Elasticity Multiplier"
                  value={spec.feeMarket.elasticityMultiplier}
                  tip="How much block size can stretch above target"
                />
                <Row
                  label="Min Gas Multiplier"
                  value={spec.feeMarket.minGasMultiplier}
                  tip="Floor for the gas multiplier to prevent fees from hitting zero"
                />
              </Card>
              <Card title="Staking">
                <Row
                  label="Bond Denom"
                  value={spec.staking.bondDenom}
                  mono
                  tip="The token used for staking"
                />
                <Row
                  label="Max Validators"
                  value={spec.staking.maxValidators}
                  tip="Maximum number of validators that can be active at once"
                />
                <Row
                  label="Unbonding Period"
                  value={spec.staking.unbondingPeriod}
                  tip="How long tokens are locked after you unstake"
                />
                <Row
                  label="Max Entries"
                  value={spec.staking.maxEntries}
                  tip="Max pending unbond/redelegate operations per account"
                />
                <Row
                  label="Historical Entries"
                  value={spec.staking.historicalEntries.toLocaleString()}
                  tip="How many past validator sets the chain remembers"
                />
                <Row
                  label="Min Commission"
                  value={spec.staking.minCommissionRate}
                  tip="Minimum fee validators must charge their delegators"
                />
              </Card>
              <Card title="Slashing">
                <Row
                  label="Signed Blocks Window"
                  value={spec.slashing.signedBlocksWindow.toLocaleString()}
                  tip="Number of recent blocks checked for validator uptime"
                />
                <Row
                  label="Min Signed / Window"
                  value={spec.slashing.minSignedPerWindow}
                  tip="Minimum blocks a validator must sign to avoid penalty"
                />
                <Row
                  label="Downtime Jail"
                  value={spec.slashing.downtimeJailDuration}
                  tip="How long a validator is jailed for being offline"
                />
                <Row
                  label="Double Sign Slash"
                  value={spec.slashing.slashFractionDoubleSign}
                  tip="Percentage of staked tokens burned for signing conflicting blocks"
                />
                <Row
                  label="Downtime Slash"
                  value={spec.slashing.slashFractionDowntime}
                  tip="Percentage of staked tokens burned for going offline"
                />
                <Row
                  label="Slash Destination"
                  value={spec.slashing.slashDestination}
                  tip="Slashed tokens are permanently destroyed, reducing total supply"
                />
              </Card>
            </div>
            <div className="grid md:grid-cols-2 gap-4 mt-4">
              <Card title="Distribution">
                <Row
                  label="Community Tax"
                  value={spec.distribution.communityTax}
                  tip="Percentage of rewards sent to the community pool"
                />
                <Row
                  label="Withdraw Address"
                  value={spec.distribution.withdrawAddrEnabled}
                  tip="Whether stakers can set a different address to receive rewards"
                />
                <Row
                  label="Base Proposer Reward"
                  value={spec.distribution.baseProposerReward}
                  tip="Extra reward for the validator that proposes the block"
                />
                <Row
                  label="Bonus Proposer Reward"
                  value={spec.distribution.bonusProposerReward}
                  tip="Additional reward based on how many validators signed"
                />
              </Card>
              <Card title="Consensus Limits">
                <Row
                  label="Max Block Size"
                  value={spec.consensus.maxBytes}
                  tip="Maximum size of a single block in bytes"
                />
                <Row
                  label="Max Gas per Block"
                  value={spec.consensus.maxGas}
                  tip="Maximum total gas that can be consumed in one block"
                />
                <Row
                  label="Evidence Max Age"
                  value={spec.consensus.evidenceMaxAge}
                  tip="How far back the chain looks for validator misbehavior evidence"
                />
                <Row
                  label="Evidence Max Size"
                  value={spec.consensus.evidenceMaxBytes}
                  tip="Maximum size of misbehavior evidence in a single block"
                />
              </Card>
            </div>
          </section>

          {/* Governance */}
          <section className="animate-fade-in-delay-3">
            <SectionHeading
              id="governance"
              title="Governance"
              subtitle="On-chain governance proposal and voting parameters"
            />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Deposits">
                <Row
                  label="Min Deposit"
                  value={spec.governance.minDepositDisplay}
                  tip="Minimum tokens needed to submit a governance proposal"
                />
                <Row
                  label="Min Deposit (airl)"
                  value={spec.governance.minDeposit}
                  mono
                  tip="Same amount in the smallest token unit"
                />
                <Row
                  label="Expedited Deposit"
                  value={spec.governance.expeditedMinDepositDisplay}
                  tip="Higher deposit for urgent proposals that vote faster"
                />
                <Row
                  label="Initial Deposit Ratio"
                  value={spec.governance.minInitialDepositRatio}
                  tip="How much of the deposit must be paid upfront"
                />
              </Card>
              <Card title="Voting">
                <Row
                  label="Voting Period"
                  value={spec.governance.votingPeriod}
                  tip="How long token holders can vote on a proposal"
                />
                <Row
                  label="Expedited Voting"
                  value={spec.governance.expeditedVotingPeriod}
                  tip="Shorter voting window for urgent proposals"
                />
                <Row
                  label="Max Deposit Period"
                  value={spec.governance.maxDepositPeriod}
                  tip="Time limit to reach the minimum deposit or proposal is canceled"
                />
                <Row
                  label="Quorum"
                  value={spec.governance.quorum}
                  tip="Minimum voter participation for a vote to count"
                />
                <Row
                  label="Threshold"
                  value={spec.governance.threshold}
                  tip="Percentage of Yes votes needed to pass"
                />
                <Row
                  label="Veto Threshold"
                  value={spec.governance.vetoThreshold}
                  tip="If this many vote No With Veto, proposal fails and deposit is burned"
                />
                <Row
                  label="Burn Vote Veto"
                  value={spec.governance.burnVoteVeto}
                  tip="Whether the deposit is burned when a proposal is vetoed"
                />
                <Row
                  label="Cancel Ratio"
                  value={spec.governance.proposalCancelRatio}
                  tip="Percentage of deposit burned if proposer cancels their own proposal"
                />
              </Card>
            </div>
          </section>

          {/* EVM */}
          <section className="animate-fade-in-delay-3">
            <SectionHeading
              id="evm"
              title="EVM Extensions"
              subtitle="EVM configuration, precompiles, predeployed contracts, ERC-20, and IBC"
            />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="EVM Configuration">
                <Row
                  label="EVM Denom"
                  value={spec.evm.evmDenom}
                  mono
                  tip="Token used to pay gas fees on the EVM side"
                />
                <Row
                  label="Contract Deploy"
                  value={spec.evm.accessControlCreate}
                  tip="Who can deploy smart contracts — anyone or restricted"
                />
                <Row
                  label="Contract Call"
                  value={spec.evm.accessControlCall}
                  tip="Who can call smart contracts — anyone or restricted"
                />
                <Row
                  label="Extra EIPs"
                  value={spec.evm.extraEips.join(", ")}
                  tip="Additional Ethereum Improvement Proposals enabled: MCOPY (5656), Transient Storage (1153), SELFDESTRUCT changes (6780)"
                />
                <Row
                  label="History Window"
                  value={spec.evm.historyServeWindow.toLocaleString()}
                  tip="Number of recent blocks served for eth_getLogs and similar queries"
                />
              </Card>
              <Card title="Cross-Chain & Tokens">
                <Row
                  label="ERC-20 Module"
                  value={spec.erc20.enabled}
                  tip="Bridges between native Cosmos tokens and ERC-20 on the EVM"
                />
                <Row
                  label="ERC-20 Registration"
                  value={
                    spec.erc20.permissionlessRegistration
                      ? "Permissionless"
                      : "Restricted"
                  }
                  tip="Anyone can register a new Cosmos token as ERC-20 without governance"
                />
                <Row
                  label="IBC Send"
                  value={spec.ibc.sendEnabled}
                  tip="Whether tokens can be sent to other blockchains via IBC"
                />
                <Row
                  label="IBC Receive"
                  value={spec.ibc.receiveEnabled}
                  tip="Whether tokens can be received from other blockchains via IBC"
                />
                <Row
                  label="IBC Clients"
                  value={spec.ibc.allowedClients}
                  tip="Which light client types can connect — wildcard means any chain"
                />
              </Card>
              <Card
                title={`Static Precompiles (${spec.precompiles.length})`}
                className="md:col-span-2"
              >
                <div className="grid md:grid-cols-2 gap-x-6">
                  <div>
                    {spec.precompiles.slice(0, 5).map((p) => (
                      <AddressRow key={p.address} {...p} />
                    ))}
                  </div>
                  <div>
                    {spec.precompiles.slice(5).map((p) => (
                      <AddressRow key={p.address} {...p} />
                    ))}
                  </div>
                </div>
              </Card>
              <Card
                title={`Predeployed Contracts (${spec.predeployed.length})`}
                className="md:col-span-2"
              >
                <div className="grid md:grid-cols-2 gap-x-6">
                  <div>
                    {spec.predeployed.slice(0, 3).map((p) => (
                      <AddressRow key={p.address} {...p} />
                    ))}
                  </div>
                  <div>
                    {spec.predeployed.slice(3).map((p) => (
                      <AddressRow key={p.address} {...p} />
                    ))}
                  </div>
                </div>
              </Card>
            </div>
          </section>

          {/* Modules */}
          <section className="animate-fade-in-delay-3">
            <SectionHeading
              id="modules"
              title="Modules"
              subtitle="Cosmos SDK and EVM modules included in the chain"
            />
            <Card title={`Active Modules (${spec.modules.length})`}>
              <div className="flex flex-wrap gap-2">
                {spec.modules.map((m) => {
                  const isEvm = [
                    "evm",
                    "erc20",
                    "feemarket",
                    "precisebank",
                  ].includes(m);
                  const isIbc = m.startsWith("ibc");
                  const desc = moduleDescriptions[m];
                  return (
                    <span
                      key={m}
                      className={`tip-wrapper module-tag relative inline-flex items-center rounded-lg px-3 py-1.5 text-xs font-mono font-medium border cursor-help ${
                        isEvm
                          ? "bg-accent-soft text-accent border-accent/20"
                          : isIbc
                            ? "bg-info/10 text-info border-info/20"
                            : "bg-bg-elevated text-text-secondary border-border"
                      }`}
                    >
                      {m}
                      {desc && (
                        <span className="tip-bubble absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2 rounded-lg bg-bg-elevated border border-border text-xs text-text-secondary whitespace-normal max-w-[220px] text-center opacity-0 pointer-events-none transition-opacity duration-200 z-50 shadow-lg font-sans">
                          {desc}
                        </span>
                      )}
                    </span>
                  );
                })}
              </div>
              <div className="flex items-center gap-4 mt-4 text-xs text-text-muted">
                <span className="flex items-center gap-1.5">
                  <span className="h-2 w-2 rounded-full bg-accent" /> EVM
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="h-2 w-2 rounded-full bg-info" /> IBC
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="h-2 w-2 rounded-full bg-text-muted" /> Cosmos
                  SDK
                </span>
              </div>
            </Card>
          </section>

          {/* Infrastructure */}
          <section className="animate-fade-in-delay-3">
            <SectionHeading
              id="infrastructure"
              title="Infrastructure"
              subtitle={`Validator network topology for ${network}`}
            />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Network Overview">
                <Row
                  label="Active Validators"
                  value={spec.infrastructure.validators}
                  tip="Number of validators securing this network"
                />
                <Row
                  label="Voting Power Each"
                  value={spec.infrastructure.votingPowerEach}
                  tip="Equal distribution — each validator has the same weight"
                />
                <Row
                  label="Cloud Providers"
                  value={`${new Set(spec.infrastructure.servers.map((s) => s.provider)).size} providers`}
                  tip="Distributed across multiple providers for resilience"
                />
                <Row
                  label="Consensus"
                  value="CometBFT (>2/3)"
                  tip="Blocks require >66% of voting power to be produced"
                />
              </Card>
              <Card
                title={`Validator Nodes (${spec.infrastructure.servers.length})`}
              >
                {spec.infrastructure.servers.map((s) => (
                  <div
                    key={s.name}
                    className="data-row py-3 border-b border-border last:border-0"
                  >
                    <div className="flex items-center justify-between gap-2 mb-1">
                      <span className="text-sm font-medium text-text-primary">
                        {s.name}
                      </span>
                      <span className="text-xs font-mono px-2 py-0.5 rounded-md bg-bg-elevated text-text-muted">
                        {s.provider}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-xs text-text-muted">{s.role}</span>
                      <span className="text-xs text-text-muted">
                        {s.location}
                      </span>
                    </div>
                  </div>
                ))}
              </Card>
            </div>
          </section>

          {/* Endpoints */}
          <section className="animate-fade-in-delay-3">
            <SectionHeading
              id="endpoints"
              title="Endpoints"
              subtitle={`Public RPC endpoints for ${network}`}
            />
            <Card title="Public Endpoints">
              <EndpointRow
                label="Cosmos RPC"
                url={spec.endpoints.rpc}
                tip="Query blockchain data and broadcast transactions (Cosmos-native)"
              />
              <EndpointRow
                label="REST / LCD"
                url={spec.endpoints.rest}
                tip="HTTP API for querying chain state (balances, proposals, etc.)"
              />
              <EndpointRow
                label="gRPC"
                url={spec.endpoints.grpc}
                tip="High-performance API for apps and services"
              />
              <EndpointRow
                label="EVM JSON-RPC"
                url={spec.endpoints.evmRpc}
                tip="Ethereum-compatible API — connect MetaMask and dApps here"
              />
              <EndpointRow
                label="EVM WebSocket"
                url={spec.endpoints.evmWs}
                tip="Real-time event streaming for EVM apps"
              />
              <EndpointRow
                label="Explorer"
                url={spec.endpoints.explorer}
                tip="Browse blocks, transactions, and accounts"
              />
              <EndpointRow
                label="EVM Explorer"
                url={spec.endpoints.evmExplorer}
                tip="Ethereum-style block explorer (Blockscout)"
              />
            </Card>
          </section>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-border py-8 px-6">
        <div className="mx-auto max-w-6xl flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <IntegraLogo
              variant="mark"
              color={theme === "dark" ? "white" : "brand"}
              className="h-5 w-5"
            />
            <span className="text-sm font-medium text-text-secondary">
              Integra Layer
            </span>
          </div>
          <div className="text-xs text-text-muted">
            Source of truth for all chain parameters.
          </div>
        </div>
      </footer>
    </div>
  );
}
