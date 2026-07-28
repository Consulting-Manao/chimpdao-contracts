const KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"];

function appendAmount(current: string, key: string): string {
  if (key === "⌫") return current.length <= 1 ? "0" : current.slice(0, -1);
  if (key === ".") return current.includes(".") ? current : current + ".";
  if (current === "0") return key;
  const [, frac] = current.split(".");
  if (frac && frac.length >= 6) return current;
  if (current.replace(".", "").length >= 12) return current;
  return current + key;
}

export function AmountEntry({
  amount,
  symbol,
  onChange,
  onPay,
  canPay,
  note,
}: {
  amount: string;
  symbol: string;
  onChange: (v: string) => void;
  onPay: () => void;
  canPay: boolean;
  note?: string;
}) {
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
          <span className="amount-unit">{symbol}</span>
        </p>
      </div>

      <div className="keypad">
        {KEYS.map((k) => (
          <button
            key={k}
            type="button"
            className={k === "." || k === "⌫" ? "key soft" : "key"}
            onClick={() => onChange(appendAmount(amount, k))}
          >
            {k}
          </button>
        ))}
      </div>

      <button type="button" className="cta" disabled={!canPay} onClick={onPay}>
        Charge
      </button>
      {note ? <p className="note">{note}</p> : null}
    </div>
  );
}
