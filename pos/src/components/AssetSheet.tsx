import { useEffect } from "react";
import type { Asset } from "../chain/assets.ts";
import { CHAIN_NAMES } from "../chain/assets.ts";

export function AssetSheet({
  assets,
  current,
  onSelect,
  onClose,
}: {
  assets: Asset[];
  current: Asset;
  onSelect: (asset: Asset) => void;
  onClose: () => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="sheet-wrap" onClick={onClose}>
      <div
        className="sheet"
        role="dialog"
        aria-label="Pay with"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="sheet-title">Pay with</h2>
        <ul className="sheet-list">
          {assets.map((asset) => (
            <li key={asset.id}>
              <button
                type="button"
                className="sheet-row"
                disabled={Boolean(asset.unavailable)}
                aria-current={asset.id === current.id || undefined}
                onClick={() => {
                  onSelect(asset);
                  onClose();
                }}
              >
                <span className="sheet-code">{asset.code}</span>
                <span className="sheet-meta">
                  {asset.unavailable ?? CHAIN_NAMES[asset.chain]}
                </span>
                {asset.id === current.id ? (
                  <span className="sheet-tick" aria-hidden>
                    ✓
                  </span>
                ) : null}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
