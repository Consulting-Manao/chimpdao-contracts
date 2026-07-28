import { useState } from "react";
import type { Asset } from "../chain/assets.ts";
import { AssetSheet } from "./AssetSheet.tsx";

const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"];

function appendAmount(current: string, key: string, decimals: number): string {
  if (key === "⌫") return current.length <= 1 ? "0" : current.slice(0, -1);
  if (key === ".") return current.includes(".") ? current : current + ".";
  if (current === "0") return key;
  const [, frac] = current.split(".");
  if (frac && frac.length >= decimals) return current;
  if (current.replace(".", "").length >= 12) return current;
  return current + key;
}

/** Switching to a coarser asset must not leave unpayable decimals on screen. */
function clampAmount(amount: string, decimals: number): string {
  const [whole = "0", frac] = amount.split(".");
  if (!frac || frac.length <= decimals) return amount;
  return decimals ? `${whole}.${frac.slice(0, decimals)}` : whole;
}

// ponytail: assert the keypad honours the asset's decimals in both directions
if (import.meta.env.DEV) {
  const checks: [string, string][] = [
    [appendAmount("1.23", "4", 2), "1.23"],
    [appendAmount("1.2", "3", 2), "1.23"],
    [clampAmount("1.234567", 2), "1.23"],
    [clampAmount("1.2", 6), "1.2"],
  ];
  for (const [got, want] of checks) {
    if (got !== want) console.warn(`amount keypad: ${got} !== ${want}`);
  }
}

export function AmountEntry({
  amount,
  asset,
  assets,
  onChange,
  onSelectAsset,
  onPay,
  canPay,
  note,
}: {
  amount: string;
  asset: Asset;
  assets: Asset[];
  onChange: (v: string) => void;
  onSelectAsset: (asset: Asset) => void;
  onPay: () => void;
  canPay: boolean;
  note?: string;
}) {
  const [picking, setPicking] = useState(false);
  const [whole, frac] = amount.split(".");

  return (
    <div className="stage">
      <div className="amount">
        <span className="micro">Amount</span>
        <p className="amount-value">
          {whole}
          {amount.includes(".") ? (
            <span className="amount-frac">.{frac ?? ""}</span>
          ) : null}
          <button
            type="button"
            className="asset-pill"
            aria-label={`Pay with ${asset.code}, change`}
            onClick={() => setPicking(true)}
          >
            {asset.code}
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
              <path d="M6 9.5l6 6 6-6" />
            </svg>
          </button>
        </p>
      </div>

      <div className="keypad">
        {KEYS.map((k) => (
          <button
            key={k}
            type="button"
            className={k === "." || k === "⌫" ? "key soft" : "key"}
            onClick={() => onChange(appendAmount(amount, k, asset.decimals))}
          >
            {k}
          </button>
        ))}
      </div>

      <button type="button" className="cta" disabled={!canPay} onClick={onPay}>
        Charge
      </button>
      {note ? <p className="note">{note}</p> : null}

      {picking ? (
        <AssetSheet
          assets={assets}
          current={asset}
          onSelect={(next) => {
            onSelectAsset(next);
            onChange(clampAmount(amount, next.decimals));
          }}
          onClose={() => setPicking(false)}
        />
      ) : null}
    </div>
  );
}
