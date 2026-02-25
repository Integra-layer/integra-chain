"use client";

import { useState } from "react";
import { chainSpecs, type Network } from "./chain-data";

function NetworkToggle({ network, onChange }: { network: Network; onChange: (n: Network) => void }) {
  return (
    <div className="relative flex items-center rounded-full bg-bg-elevated p-1 border border-border">
      <button
        onClick={() => onChange("mainnet")}
        className={`relative z-10 rounded-full px-5 py-2 text-sm font-medium transition-all duration-300 cursor-pointer ${
          network === "mainnet" ? "text-white" : "text-text-muted hover:text-text-secondary"
        }`}
      >
        Mainnet
      </button>
      <button
        onClick={() => onChange("testnet")}
        className={`relative z-10 rounded-full px-5 py-2 text-sm font-medium transition-all duration-300 cursor-pointer ${
          network === "testnet" ? "text-white" : "text-text-muted hover:text-text-secondary"
        }`}
      >
        Testnet
      </button>
      <div
        className="absolute top-1 h-[calc(100%-8px)] rounded-full transition-all duration-300 ease-out"
        style={{
          left: network === "mainnet" ? "4px" : "calc(50% + 0px)",
          width: "calc(50% - 4px)",
          background: network === "mainnet"
            ? "linear-gradient(135deg, #FC4E23, #FF6D49)"
            : "linear-gradient(135deg, #F34499, #FF6D49)",
        }}
      />
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full bg-success/10 px-3 py-1 text-sm font-medium text-success">
      <span className="h-2 w-2 rounded-full bg-success" style={{ animation: "pulse-dot 2s ease-in-out infinite" }} />
      {status}
    </span>
  );
}

function Card({ title, children, className = "" }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={`rounded-2xl border border-border bg-bg-card p-6 transition-all duration-300 hover:border-border-strong hover:bg-bg-elevated ${className}`}>
      <h3 className="mb-4 text-lg font-semibold text-text-primary">{title}</h3>
      {children}
    </div>
  );
}

function Row({ label, value, mono = false }: { label: string; value: string | number | boolean; mono?: boolean }) {
  const display = typeof value === "boolean" ? (value ? "Yes" : "No") : String(value);
  return (
    <div className="flex items-start justify-between gap-4 py-2.5 border-b border-border last:border-0">
      <span className="text-sm text-text-muted shrink-0">{label}</span>
      <span className={`text-sm text-text-primary text-right ${mono ? "font-mono" : "font-medium"}`}>{display}</span>
    </div>
  );
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      onClick={() => { navigator.clipboard.writeText(text); setCopied(true); setTimeout(() => setCopied(false), 2000); }}
      className="ml-2 text-xs text-text-muted hover:text-brand transition-colors cursor-pointer"
      title="Copy to clipboard"
    >
      {copied ? "Copied!" : "Copy"}
    </button>
  );
}

function AddressRow({ name, address, description }: { name: string; address: string; description: string }) {
  return (
    <div className="py-3 border-b border-border last:border-0">
      <div className="flex items-center justify-between gap-2 mb-1">
        <span className="text-sm font-medium text-text-primary">{name}</span>
        <div className="flex items-center">
          <code className="text-xs font-mono text-brand">{address.slice(0, 10)}...{address.slice(-6)}</code>
          <CopyButton text={address} />
        </div>
      </div>
      <p className="text-xs text-text-muted">{description}</p>
    </div>
  );
}

function EndpointRow({ label, url }: { label: string; url: string }) {
  return (
    <div className="flex items-center justify-between gap-4 py-2.5 border-b border-border last:border-0">
      <span className="text-sm text-text-muted">{label}</span>
      <div className="flex items-center">
        <code className="text-xs font-mono text-info">{url}</code>
        <CopyButton text={url} />
      </div>
    </div>
  );
}

function SectionHeading({ id, title, subtitle }: { id: string; title: string; subtitle: string }) {
  return (
    <div id={id} className="mb-6 scroll-mt-24">
      <h2 className="text-2xl font-bold text-text-primary mb-1">{title}</h2>
      <p className="text-sm text-text-muted">{subtitle}</p>
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
  { id: "endpoints", label: "Endpoints" },
];

export default function Home() {
  const [network, setNetwork] = useState<Network>("mainnet");
  const spec = chainSpecs[network];

  return (
    <div className="min-h-screen">
      {/* Ambient glow */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-40 left-1/2 -translate-x-1/2 w-[800px] h-[400px] rounded-full opacity-20 blur-[120px] gradient-brand-bg" />
        <div className="absolute top-1/3 -right-40 w-[500px] h-[500px] rounded-full opacity-10 blur-[100px] bg-brand-pink" />
      </div>

      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 border-b border-border bg-bg/80 backdrop-blur-xl">
        <div className="mx-auto max-w-6xl flex items-center justify-between px-6 py-3">
          <div className="flex items-center gap-3">
            <div className="h-8 w-8 rounded-lg gradient-brand-bg flex items-center justify-center text-white font-bold text-sm">
              I
            </div>
            <span className="text-sm font-semibold text-text-primary hidden sm:inline">Integra Layer</span>
            <span className="text-xs text-text-muted hidden md:inline">Chain Specification</span>
          </div>
          <div className="flex items-center gap-4">
            <nav className="hidden lg:flex items-center gap-1">
              {sections.map((s) => (
                <a key={s.id} href={`#${s.id}`} className="px-3 py-1.5 text-xs text-text-muted hover:text-text-primary transition-colors rounded-lg hover:bg-bg-elevated">
                  {s.label}
                </a>
              ))}
            </nav>
            <NetworkToggle network={network} onChange={setNetwork} />
          </div>
        </div>
      </nav>

      {/* Hero */}
      <header className="relative pt-28 pb-16 px-6">
        <div className="mx-auto max-w-6xl">
          <div className="flex flex-col items-center text-center mb-12">
            <div className="mb-6 animate-float">
              <div className="h-20 w-20 rounded-2xl gradient-brand-bg glow-brand-strong flex items-center justify-center text-white text-3xl font-bold">
                I
              </div>
            </div>
            <h1 className="text-4xl sm:text-5xl font-bold mb-3">
              <span className="gradient-brand-text">Integra Layer</span>
            </h1>
            <p className="text-lg text-text-secondary mb-6 max-w-lg">
              EVM-compatible Cosmos SDK blockchain for real-world asset tokenization
            </p>
            <div className="flex items-center gap-4">
              <StatusBadge status={spec.network.status} />
              <span className="text-sm font-mono text-text-muted">{spec.network.chainId}</span>
              <span className="text-xs px-2.5 py-1 rounded-full border border-border font-mono text-text-muted">
                EIP-155: {spec.network.evmChainId}
              </span>
            </div>
          </div>

          {/* Quick stats */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-16">
            {[
              { label: "EVM Chain ID", value: String(spec.network.evmChainId), accent: true },
              { label: "Block Time", value: spec.mint.blockTime, accent: false },
              { label: "Total Supply", value: "100B IRL", accent: false },
              { label: "Inflation", value: spec.mint.inflation, accent: false },
            ].map((stat) => (
              <div key={stat.label} className="rounded-xl border border-border bg-bg-card p-4 text-center transition-all hover:border-border-strong">
                <div className={`text-2xl font-bold mb-1 ${stat.accent ? "gradient-brand-text" : "text-text-primary"}`}>
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

          {/* Identity & Network */}
          <section>
            <SectionHeading id="identity" title="Identity" subtitle="Core chain identification and software versions" />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Chain Identity">
                <Row label="Name" value={spec.identity.name} />
                <Row label="Binary" value={spec.identity.binary} mono />
                <Row label="Bech32 Prefix" value={spec.identity.bech32Prefix} mono />
                <Row label="Home Directory" value={spec.identity.homeDir} mono />
                <Row label="Chain ID" value={spec.network.chainId} mono />
                <Row label="EVM Chain ID" value={spec.network.evmChainId} mono />
              </Card>
              <Card title="Software Versions">
                <Row label="EVM Framework" value={spec.identity.evmFramework} />
                <Row label="Cosmos SDK" value={spec.identity.cosmosSDK} />
                <Row label="CometBFT" value={spec.identity.cometBFT} />
                <Row label="EIP-1559" value={spec.feeMarket.eip1559Enabled} />
                <Row label="Precompiles" value={`${spec.precompiles.length} static`} />
                <Row label="IBC" value="Enabled (v10)" />
              </Card>
            </div>
          </section>

          {/* Token */}
          <section>
            <SectionHeading id="token" title="Token" subtitle="Native token denomination and supply configuration" />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Token Info">
                <Row label="Name" value={spec.token.name} />
                <Row label="Symbol" value={spec.token.symbol} />
                <Row label="Base Denom" value={spec.token.baseDenom} mono />
                <Row label="Display Denom" value={spec.token.displayDenom} />
                <Row label="Decimals" value={spec.token.decimals} />
                <Row label="Total Supply" value={spec.token.totalSupply} />
              </Card>
              <Card title="Denomination Guide">
                <div className="space-y-4">
                  <div className="rounded-xl bg-bg-elevated p-4">
                    <div className="text-xs text-text-muted mb-2">Conversion</div>
                    <div className="text-sm font-mono text-text-primary">
                      1 IRL = 10<sup>18</sup> airl
                    </div>
                    <div className="text-xs text-text-muted mt-1">Similar to ETH / wei relationship</div>
                  </div>
                  <div className="rounded-xl bg-bg-elevated p-4">
                    <div className="text-xs text-text-muted mb-2">Naming</div>
                    <div className="space-y-1">
                      <div className="flex justify-between text-sm">
                        <span className="text-text-muted">Base unit</span>
                        <code className="font-mono text-brand">airl</code>
                      </div>
                      <div className="flex justify-between text-sm">
                        <span className="text-text-muted">Display unit</span>
                        <code className="font-mono text-brand-gold">IRL</code>
                      </div>
                      <div className="flex justify-between text-sm">
                        <span className="text-text-muted">&quot;a&quot; prefix</span>
                        <span className="text-text-secondary">atto (10<sup>-18</sup>)</span>
                      </div>
                    </div>
                  </div>
                </div>
              </Card>
            </div>
          </section>

          {/* Consensus & Economics */}
          <section>
            <SectionHeading id="consensus" title="Consensus & Economics" subtitle="Staking, inflation, fee market, slashing, and distribution parameters" />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Mint / Inflation">
                <Row label="Inflation" value={spec.mint.inflation} />
                <Row label="Min Inflation" value={spec.mint.inflationMin} />
                <Row label="Max Inflation" value={spec.mint.inflationMax} />
                <Row label="Rate Change" value={spec.mint.inflationRateChange} />
                <Row label="Goal Bonded" value={spec.mint.goalBonded} />
                <Row label="Blocks / Year" value={spec.mint.blocksPerYear.toLocaleString()} />
                <Row label="Block Time" value={spec.mint.blockTime} />
              </Card>
              <Card title="Fee Market (EIP-1559)">
                <Row label="EIP-1559 Enabled" value={spec.feeMarket.eip1559Enabled} />
                <Row label="Base Fee" value={spec.feeMarket.baseFeeGwei} />
                <Row label="Base Fee (airl)" value={spec.feeMarket.baseFee} mono />
                <Row label="Min Gas Price" value={spec.feeMarket.minGasPrice} mono />
                <Row label="Change Denominator" value={spec.feeMarket.baseFeeChangeDenominator} />
                <Row label="Elasticity Multiplier" value={spec.feeMarket.elasticityMultiplier} />
                <Row label="Min Gas Multiplier" value={spec.feeMarket.minGasMultiplier} />
              </Card>
              <Card title="Staking">
                <Row label="Bond Denom" value={spec.staking.bondDenom} mono />
                <Row label="Max Validators" value={spec.staking.maxValidators} />
                <Row label="Unbonding Period" value={spec.staking.unbondingPeriod} />
                <Row label="Max Entries" value={spec.staking.maxEntries} />
                <Row label="Historical Entries" value={spec.staking.historicalEntries.toLocaleString()} />
                <Row label="Min Commission" value={spec.staking.minCommissionRate} />
              </Card>
              <Card title="Slashing">
                <Row label="Signed Blocks Window" value={spec.slashing.signedBlocksWindow.toLocaleString()} />
                <Row label="Min Signed / Window" value={spec.slashing.minSignedPerWindow} />
                <Row label="Downtime Jail" value={spec.slashing.downtimeJailDuration} />
                <Row label="Double Sign Slash" value={spec.slashing.slashFractionDoubleSign} />
                <Row label="Downtime Slash" value={spec.slashing.slashFractionDowntime} />
              </Card>
            </div>
            <div className="grid md:grid-cols-2 gap-4 mt-4">
              <Card title="Distribution">
                <Row label="Community Tax" value={spec.distribution.communityTax} />
                <Row label="Withdraw Address" value={spec.distribution.withdrawAddrEnabled} />
              </Card>
              <div /> {/* Spacer for grid alignment */}
            </div>
          </section>

          {/* Governance */}
          <section>
            <SectionHeading id="governance" title="Governance" subtitle="On-chain governance proposal and voting parameters" />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title="Deposits">
                <Row label="Min Deposit" value={spec.governance.minDepositDisplay} />
                <Row label="Min Deposit (airl)" value={spec.governance.minDeposit} mono />
                <Row label="Expedited Deposit" value={spec.governance.expeditedMinDepositDisplay} />
                <Row label="Initial Deposit Ratio" value={spec.governance.minInitialDepositRatio} />
              </Card>
              <Card title="Voting">
                <Row label="Voting Period" value={spec.governance.votingPeriod} />
                <Row label="Expedited Voting" value={spec.governance.expeditedVotingPeriod} />
                <Row label="Max Deposit Period" value={spec.governance.maxDepositPeriod} />
                <Row label="Quorum" value={spec.governance.quorum} />
                <Row label="Threshold" value={spec.governance.threshold} />
                <Row label="Veto Threshold" value={spec.governance.vetoThreshold} />
                <Row label="Burn Vote Veto" value={spec.governance.burnVoteVeto} />
              </Card>
            </div>
          </section>

          {/* EVM */}
          <section>
            <SectionHeading id="evm" title="EVM Extensions" subtitle="Static precompiles and predeployed contracts accessible from Solidity" />
            <div className="grid md:grid-cols-2 gap-4">
              <Card title={`Static Precompiles (${spec.precompiles.length})`} className="md:col-span-2">
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
              <Card title="Predeployed Contracts" className="md:col-span-2">
                {spec.predeployed.map((p) => (
                  <AddressRow key={p.address} {...p} />
                ))}
              </Card>
            </div>
          </section>

          {/* Modules */}
          <section>
            <SectionHeading id="modules" title="Modules" subtitle="Cosmos SDK and EVM modules included in the chain" />
            <Card title={`Active Modules (${spec.modules.length})`}>
              <div className="flex flex-wrap gap-2">
                {spec.modules.map((m) => {
                  const isEvm = ["evm", "erc20", "feemarket"].includes(m);
                  const isIbc = m.startsWith("ibc");
                  return (
                    <span
                      key={m}
                      className={`inline-flex items-center rounded-lg px-3 py-1.5 text-xs font-mono font-medium border transition-colors ${
                        isEvm
                          ? "bg-brand/10 text-brand border-brand/20"
                          : isIbc
                          ? "bg-info/10 text-info border-info/20"
                          : "bg-bg-elevated text-text-secondary border-border"
                      }`}
                    >
                      {m}
                    </span>
                  );
                })}
              </div>
              <div className="flex items-center gap-4 mt-4 text-xs text-text-muted">
                <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-brand" /> EVM</span>
                <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-info" /> IBC</span>
                <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-text-muted" /> Cosmos SDK</span>
              </div>
            </Card>
          </section>

          {/* Endpoints */}
          <section>
            <SectionHeading id="endpoints" title="Endpoints" subtitle={`Public RPC endpoints for ${network}`} />
            <Card title="Public Endpoints">
              <EndpointRow label="Cosmos RPC" url={spec.endpoints.rpc} />
              <EndpointRow label="REST / LCD" url={spec.endpoints.rest} />
              <EndpointRow label="gRPC" url={spec.endpoints.grpc} />
              <EndpointRow label="EVM JSON-RPC" url={spec.endpoints.evmRpc} />
              <EndpointRow label="EVM WebSocket" url={spec.endpoints.evmWs} />
              <EndpointRow label="Explorer" url={spec.endpoints.explorer} />
              <EndpointRow label="EVM Explorer" url={spec.endpoints.evmExplorer} />
            </Card>
          </section>

        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-border py-8 px-6">
        <div className="mx-auto max-w-6xl flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <div className="h-5 w-5 rounded gradient-brand-bg" />
            <span className="text-sm font-medium text-text-secondary">Integra Layer</span>
          </div>
          <div className="text-xs text-text-muted">
            Source of truth for all chain parameters. Auto-generated from on-chain configuration.
          </div>
        </div>
      </footer>
    </div>
  );
}
