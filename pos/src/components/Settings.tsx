import { useCallback, useEffect, useState } from "react";
import type { Asset, ChainId, NetworkId } from "../chain/assets.ts";
import { CHAIN_NAMES } from "../chain/assets.ts";
import { CHAINS, chainFor } from "../chain/index.ts";
import type { PaymentChain } from "../chain/types.ts";
import { clearPayments, listPayments } from "../lib/history.ts";
import type { NfcClient, NfcStatus } from "../nfc/client.ts";

const NETWORKS: NetworkId[] = ["testnet", "mainnet"];

/** One action at a time, so every button can share a single busy key. */
type Run = (key: string, fn: () => Promise<string>) => Promise<void>;

function shortAddr(a: string) {
  if (a.length < 12) return a;
  return `${a.slice(0, 8)}…${a.slice(-6)}`;
}

function when(at: number) {
  const d = new Date(at);
  return d.toDateString() === new Date().toDateString()
    ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    : d.toLocaleDateString([], { day: "2-digit", month: "short" });
}

function readerLabel(connected: boolean, status: NfcStatus) {
  if (!connected) return "Offline";
  if (!status.readerConnected) return "No reader";
  return (
    status.readerName?.replace(/Identiv |Dual Interface Reader/g, "").trim() ||
    "Connected"
  );
}

export function Settings({
  network,
  setNetwork,
  networkLocked,
  merchants,
  setMerchant,
  nfc,
  status,
  connected,
  nfcError,
  onRetry,
}: {
  network: NetworkId;
  setNetwork: (n: NetworkId) => void;
  networkLocked: boolean;
  merchants: Record<ChainId, string>;
  setMerchant: (chain: ChainId, address: string) => void;
  nfc: NfcClient;
  status: NfcStatus;
  connected: boolean;
  nfcError: string | null;
  onRetry: () => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  // Settings remounts every time it opens, so a read at mount is always fresh.
  const [history, setHistory] = useState(listPayments);

  const chains = CHAINS.map((id) => chainFor(id, network));

  const run: Run = async (key, fn) => {
    setBusy(key);
    setMsg(null);
    try {
      setMsg({ ok: true, text: await fn() });
    } catch (e) {
      setMsg({ ok: false, text: e instanceof Error ? e.message : String(e) });
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="settings">
      <section className="rows">
        <div className="row">
          <span className="row-key">Network</span>
          <div className="segmented" role="group" aria-label="Network">
            {NETWORKS.map((n) => (
              <button
                key={n}
                type="button"
                className={n === network ? "seg on" : "seg"}
                disabled={networkLocked}
                title={networkLocked ? "Finish the sale first" : undefined}
                onClick={() => setNetwork(n)}
              >
                {n === "testnet" ? "Testnet" : "Mainnet"}
              </button>
            ))}
          </div>
        </div>
        <div className="row">
          <span className="row-key">Reader</span>
          <span className="row-val">
            <span
              className={`dot ${connected && status.readerConnected ? "on" : "off"}`}
            />
            {readerLabel(connected, status)}
          </span>
        </div>
        <div className="row">
          <span className="row-key">Chip</span>
          <span className="row-val">
            <span className={`dot ${status.chipPresent ? "on" : "idle"}`} />
            {status.chipPresent ? "Ready" : "Waiting"}
          </span>
        </div>
        {nfcError ? (
          <div className="row">
            <span className="row-key">NFC server</span>
            <button type="button" className="btn-ghost" onClick={onRetry}>
              Reconnect
            </button>
          </div>
        ) : null}
      </section>

      <section className="block">
        <div className="block-head">
          <h2>Payments</h2>
          {history.length > 0 ? (
            <button
              type="button"
              className="btn-ghost"
              onClick={() => {
                if (!confirm("Clear the payment history?")) return;
                clearPayments();
                setHistory([]);
              }}
            >
              Clear
            </button>
          ) : null}
        </div>
        {history.length === 0 ? (
          <p className="mono-box empty">No payments yet</p>
        ) : (
          <ul className="history">
            {history.map((p) => (
              <li key={p.id}>
                <span className="hist-amount">
                  {p.amount} <span className="hist-symbol">{p.symbol}</span>
                </span>
                <span className="hist-meta">
                  {when(p.at)} · {CHAIN_NAMES[p.chain] ?? p.chain} ·{" "}
                  {shortAddr(p.from)}
                </span>
                <a
                  className="hist-link"
                  href={p.explorerUrl}
                  target="_blank"
                  rel="noreferrer"
                >
                  Receipt
                </a>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="block">
        <h2>Merchant</h2>
        {chains.map((chain) => (
          <MerchantBlock
            key={chain.id}
            chain={chain}
            address={merchants[chain.id]}
            setAddress={(a) => setMerchant(chain.id, a)}
            busy={busy}
            run={run}
            onError={(text) => setMsg({ ok: false, text })}
          />
        ))}
      </section>

      {chains
        .filter((chain) => chain.chipAddress)
        .map((chain) => (
          <ChipWallet
            key={chain.id}
            chain={chain}
            nfc={nfc}
            chipPresent={status.chipPresent}
            busy={busy}
            run={run}
          />
        ))}

      {msg ? (
        <p className={`settings-msg ${msg.ok ? "ok" : "err"}`}>{msg.text}</p>
      ) : null}
    </div>
  );
}

function MerchantBlock({
  chain,
  address,
  setAddress,
  busy,
  run,
  onError,
}: {
  chain: PaymentChain;
  address: string;
  setAddress: (a: string) => void;
  busy: string | null;
  run: Run;
  onError: (text: string) => void;
}) {
  const [paste, setPaste] = useState("");
  const [missing, setMissing] = useState<string[]>([]);

  // A merchant with no trust line silently cannot be paid, so say so up front.
  useEffect(() => {
    const issued = chain.assets.filter((a) => a.issuer);
    if (!address || !chain.isAddress(address) || !issued.length) {
      setMissing([]);
      return;
    }
    let live = true;
    void Promise.all(
      issued.map(async (a) => ((await chain.balance(address, a)) == null ? a.code : null)),
    ).then((codes) => {
      if (live) setMissing(codes.filter((c): c is string => c !== null));
    });
    return () => {
      live = false;
    };
  }, [chain, address]);

  const key = `merchant:${chain.id}`;

  return (
    <div className="chain-block">
      <h3>{chain.name}</h3>
      <p className={`mono-box ${address ? "" : "empty"}`}>
        {address || "No destination set"}
      </p>
      {missing.length ? (
        <p className="block-meta warn">Cannot receive {missing.join(", ")}</p>
      ) : null}
      <div className="actions">
        {chain.newMerchant ? (
          <button
            type="button"
            className="btn-primary"
            disabled={!!busy}
            onClick={() =>
              void run(key, async () => {
                const { address: created } = await chain.newMerchant!();
                setAddress(created);
                return `${chain.name} merchant funded · ${shortAddr(created)}`;
              })
            }
          >
            {busy === key ? "Creating…" : "Create & fund"}
          </button>
        ) : null}
        <button
          type="button"
          className="btn-ghost"
          disabled={!address}
          onClick={() => void navigator.clipboard.writeText(address)}
        >
          Copy
        </button>
      </div>
      <div className="paste-row">
        <input
          placeholder={`Or paste ${chain.addressHint}…`}
          value={paste}
          onChange={(e) => setPaste(e.target.value)}
          spellCheck={false}
        />
        <button
          type="button"
          className="btn-ghost"
          onClick={() => {
            const next = paste.trim();
            if (!chain.isAddress(next)) {
              onError(`Need a valid ${chain.addressHint}`);
              return;
            }
            setAddress(next);
            setPaste("");
          }}
        >
          Use
        </button>
      </div>
    </div>
  );
}

function ChipWallet({
  chain,
  nfc,
  chipPresent,
  busy,
  run,
}: {
  chain: PaymentChain;
  nfc: NfcClient;
  chipPresent: boolean;
  busy: string | null;
  run: Run;
}) {
  const [address, setAddress] = useState<string | null>(null);
  const [balances, setBalances] = useState<Record<string, string | null>>({});

  const refresh = useCallback(async () => {
    if (!chipPresent || !nfc.isConnected() || !chain.chipAddress) {
      setAddress(null);
      setBalances({});
      return;
    }
    try {
      const addr = chain.chipAddress(await nfc.readPublicKey());
      setAddress(addr);
      const pairs = await Promise.all(
        chain.assets.map(
          async (a) => [a.id, await chain.balance(addr, a)] as const,
        ),
      );
      setBalances(Object.fromEntries(pairs));
    } catch {
      setAddress(null);
      setBalances({});
    }
  }, [chain, nfc, chipPresent]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const fundKey = `fund:${chain.id}`;

  return (
    <section className="block">
      <h2>Chip wallet</h2>
      <p className={`mono-box ${address ? "" : "empty"}`}>
        {address || (chipPresent ? "Reading…" : "Place chip on the reader")}
      </p>
      {address ? (
        <ul className="asset-rows">
          {chain.assets.map((asset) => (
            <ChipAssetRow
              key={asset.id}
              chain={chain}
              asset={asset}
              balance={balances[asset.id] ?? null}
              busy={busy}
              run={run}
              onEnabled={refresh}
              nfc={nfc}
            />
          ))}
        </ul>
      ) : null}
      <div className="actions">
        {chain.fund ? (
          <button
            type="button"
            className="btn-primary"
            disabled={!!busy || !chipPresent}
            onClick={() =>
              void run(fundKey, async () => {
                if (!address) throw new Error("Place the chip on the reader");
                await chain.fund!(address);
                await refresh();
                return "Chip funded";
              })
            }
          >
            {busy === fundKey ? "Funding…" : "Fund chip"}
          </button>
        ) : null}
        <button
          type="button"
          className="btn-ghost"
          disabled={!address}
          onClick={() => address && void navigator.clipboard.writeText(address)}
        >
          Copy
        </button>
        <button
          type="button"
          className="btn-ghost"
          disabled={!chipPresent || !!busy}
          onClick={() => void refresh()}
        >
          Refresh
        </button>
      </div>
    </section>
  );
}

function ChipAssetRow({
  chain,
  asset,
  balance,
  busy,
  run,
  onEnabled,
  nfc,
}: {
  chain: PaymentChain;
  asset: Asset;
  balance: string | null;
  busy: string | null;
  run: Run;
  onEnabled: () => Promise<void>;
  nfc: NfcClient;
}) {
  const key = `enable:${asset.id}`;
  const enableable = balance == null && asset.issuer && chain.enableAsset;

  return (
    <li className="asset-row">
      <span className="asset-code">{asset.code}</span>
      <span className={`asset-bal ${balance == null ? "empty" : ""}`}>
        {balance ?? (asset.issuer ? "Not enabled" : "Unfunded")}
      </span>
      {enableable ? (
        <button
          type="button"
          className="btn-ghost"
          disabled={!!busy}
          onClick={() =>
            void run(key, async () => {
              await chain.enableAsset!(asset, nfc);
              await onEnabled();
              return `${asset.code} enabled`;
            })
          }
        >
          {busy === key ? "Enabling…" : "Enable"}
        </button>
      ) : asset.faucet ? (
        <a className="btn-ghost" href={asset.faucet} target="_blank" rel="noreferrer">
          Top up
        </a>
      ) : null}
    </li>
  );
}
