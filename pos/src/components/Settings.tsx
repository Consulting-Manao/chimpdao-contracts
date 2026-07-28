import { useCallback, useEffect, useState } from "react";
import { activeChain } from "../chain/index.ts";
import { addressFromSec1Hex, getXrpBalance } from "../chain/xrpl.ts";
import {
  createAndFundMerchant,
  fundAddress,
} from "../chain/xrpl-faucet.ts";
import { clearPayments, listPayments } from "../lib/history.ts";
import type { NfcClient, NfcStatus } from "../nfc/client.ts";

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
  destination,
  setDestination,
  nfc,
  status,
  connected,
  nfcError,
  onRetry,
}: {
  destination: string;
  setDestination: (a: string) => void;
  nfc: NfcClient;
  status: NfcStatus;
  connected: boolean;
  nfcError: string | null;
  onRetry: () => void;
}) {
  const [paste, setPaste] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [chipAddr, setChipAddr] = useState<string | null>(null);
  const [chipBal, setChipBal] = useState<string | null>(null);
  // Settings remounts every time it opens, so a read at mount is always fresh.
  const [history, setHistory] = useState(listPayments);

  const refreshChip = useCallback(async () => {
    if (!status.chipPresent || !nfc.isConnected()) {
      setChipAddr(null);
      setChipBal(null);
      return;
    }
    try {
      const { address } = addressFromSec1Hex(await nfc.readPublicKey());
      setChipAddr(address);
      setChipBal(await getXrpBalance(address));
    } catch {
      setChipAddr(null);
      setChipBal(null);
    }
  }, [nfc, status.chipPresent]);

  useEffect(() => {
    void refreshChip();
  }, [refreshChip]);

  const run = async (
    key: string,
    fn: () => Promise<string>,
  ) => {
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

  const createMerchant = () =>
    run("merchant", async () => {
      const { address } = await createAndFundMerchant();
      setDestination(address);
      return `Merchant funded · ${shortAddr(address)}`;
    });

  const fundChip = () =>
    run("chip", async () => {
      if (!status.chipPresent) throw new Error("Place the chip on the reader");
      const { address } = addressFromSec1Hex(await nfc.readPublicKey());
      await fundAddress(address);
      setChipAddr(address);
      setChipBal(await getXrpBalance(address));
      return "Chip funded";
    });

  return (
    <div className="settings">
      <section className="rows">
        <div className="row">
          <span className="row-key">Network</span>
          <span className="row-val accent">{activeChain.networkLabel}</span>
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
                  {when(p.at)} · {shortAddr(p.from)}
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
        <p className={`mono-box ${destination ? "" : "empty"}`}>
          {destination || "No destination set"}
        </p>
        <div className="actions">
          <button
            type="button"
            className="btn-primary"
            disabled={!!busy}
            onClick={() => void createMerchant()}
          >
            {busy === "merchant" ? "Creating…" : "Create & fund"}
          </button>
          <button
            type="button"
            className="btn-ghost"
            disabled={!destination}
            onClick={() => void navigator.clipboard.writeText(destination)}
          >
            Copy
          </button>
        </div>
        <div className="paste-row">
          <input
            placeholder="Or paste r-address…"
            value={paste}
            onChange={(e) => setPaste(e.target.value)}
            spellCheck={false}
          />
          <button
            type="button"
            className="btn-ghost"
            onClick={() => {
              const next = paste.trim();
              if (!next.startsWith("r")) {
                setMsg({ ok: false, text: "Need a valid r-address" });
                return;
              }
              setDestination(next);
              setPaste("");
              setMsg({ ok: true, text: "Destination updated" });
            }}
          >
            Use
          </button>
        </div>
      </section>

      <section className="block">
        <h2>Chip wallet</h2>
        <p className={`mono-box ${chipAddr ? "" : "empty"}`}>
          {chipAddr ||
            (status.chipPresent ? "Reading…" : "Place chip on the reader")}
        </p>
        {chipAddr ? (
          <p className="block-meta">
            {chipBal != null ? `${chipBal} XRP` : "Unfunded"}
          </p>
        ) : null}
        <div className="actions">
          <button
            type="button"
            className="btn-primary"
            disabled={!!busy || !status.chipPresent}
            onClick={() => void fundChip()}
          >
            {busy === "chip" ? "Funding…" : "Fund chip"}
          </button>
          <button
            type="button"
            className="btn-ghost"
            disabled={!chipAddr}
            onClick={() =>
              chipAddr && void navigator.clipboard.writeText(chipAddr)
            }
          >
            Copy
          </button>
          <button
            type="button"
            className="btn-ghost"
            disabled={!status.chipPresent || !!busy}
            onClick={() => void refreshChip()}
          >
            Refresh
          </button>
        </div>
      </section>

      {msg ? (
        <p className={`settings-msg ${msg.ok ? "ok" : "err"}`}>{msg.text}</p>
      ) : null}
    </div>
  );
}
