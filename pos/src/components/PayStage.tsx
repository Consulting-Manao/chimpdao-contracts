import type { PaymentResult } from "../chain/types.ts";
import type { PayPhase, PayStep } from "../hooks/usePayment.ts";

/** Customers see plain language; the raw cause stays on the title attribute. */
function friendly(raw: string | null): string {
  if (!raw) return "Payment failed";
  if (/no card tapped/i.test(raw)) return "No card tapped";
  if (/public key|transmit|APDU|SELECT|signature|chip on the reader/i.test(raw)) {
    return "Card could not be read";
  }
  if (/timeout|timed out/i.test(raw)) return "Card timed out";
  if (/unfunded|insufficient/i.test(raw)) return "Insufficient balance on card";
  if (/NFC server|connection closed|Not connected/i.test(raw)) {
    return "Reader unavailable";
  }
  if (/merchant|destination/i.test(raw)) return "No merchant set";
  return "Payment failed";
}

function copy(
  phase: PayPhase,
  step: PayStep,
  chipPresent: boolean,
  error: string | null,
) {
  if (phase === "done") {
    return error
      ? { title: "Declined", hint: friendly(error) }
      : { title: "Approved", hint: "" };
  }
  if (step === "tap") {
    // Back on the tap screen with an error means the last tap didn't read.
    return error
      ? { title: "Tap again", hint: friendly(error) }
      : { title: "Tap to pay", hint: "Hold the card near the reader" };
  }
  if (step === "sign") {
    return { title: "Keep card on reader", hint: "Reading card" };
  }
  return {
    title: chipPresent ? "You can remove the card" : "Card removed",
    hint: "Confirming payment",
  };
}

/**
 * One screen for the whole transaction. Tap, read, confirm and the verdict all
 * share this frame, so the ring changes state in place instead of the layout
 * jumping when the payment lands.
 */
export function PayStage({
  phase,
  step,
  amount,
  symbol,
  chipPresent,
  result,
  error,
  onReset,
  onRetry,
}: {
  phase: PayPhase;
  step: PayStep;
  amount: string;
  symbol: string;
  chipPresent: boolean;
  result: PaymentResult | null;
  error: string | null;
  onReset: () => void;
  onRetry: () => void;
}) {
  const done = phase === "done";
  const ok = done && !error;
  const { title, hint } = copy(phase, step, chipPresent, error);
  const state = done ? (ok ? "ok" : "err") : step;

  return (
    <div className={`stage flow ${state}`}>
      <div className="flow-head">
        <span className="micro">{ok ? "Amount paid" : "Amount due"}</span>
        <p className="flow-amount">
          {amount} <span className="amount-unit">{symbol}</span>
        </p>
      </div>

      <div className={`target ${state}`}>
        {step === "tap" && !done ? (
          <>
            <span className="radar" />
            <span className="radar" />
          </>
        ) : null}
        {!done && step !== "tap" ? (
          <svg className="arc" viewBox="0 0 100 100" aria-hidden="true">
            <circle cx="50" cy="50" r="48" />
          </svg>
        ) : null}
        <span className="target-glyph">
          {done ? ok ? <Tick /> : <Cross /> : step === "submit" ? (
            <PendingTick />
          ) : (
            <Contactless />
          )}
        </span>
      </div>

      <div className="flow-copy" aria-live="polite">
        <h2 className="flow-title">{title}</h2>
        {hint ? (
          <p className="micro" title={error ?? undefined}>
            {hint}
          </p>
        ) : null}
      </div>

      <div className="flow-foot">
        {!done ? (
          step === "tap" ? (
            <button type="button" className="btn-text" onClick={onReset}>
              Cancel
            </button>
          ) : null
        ) : ok ? (
          <>
            <span className="countdown" />
            <button type="button" className="cta" onClick={onReset}>
              New payment
            </button>
            {result ? (
              <a
                className="receipt"
                href={result.explorerUrl}
                target="_blank"
                rel="noreferrer"
              >
                Receipt
              </a>
            ) : null}
          </>
        ) : (
          <>
            <button type="button" className="cta" onClick={onRetry}>
              Try again
            </button>
            <button type="button" className="btn-text" onClick={onReset}>
              Cancel
            </button>
          </>
        )}
      </div>
    </div>
  );
}

function Contactless() {
  return (
    <svg viewBox="0 0 48 48" fill="none" stroke="currentColor" aria-hidden="true">
      <path d="M13 15a20 20 0 0 1 0 18" strokeWidth="2.6" />
      <path d="M20 12.5a26 26 0 0 1 0 23" strokeWidth="2.6" />
      <path d="M27 10a32 32 0 0 1 0 28" strokeWidth="2.6" />
      <path d="M34 7.5a38 38 0 0 1 0 33" strokeWidth="2.6" />
    </svg>
  );
}

/** Dashed tick: the card is done, the payment is not confirmed yet. */
function PendingTick() {
  return (
    <svg
      className="glyph-pending"
      viewBox="0 0 48 48"
      fill="none"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path d="M9 25l11 11 19-21" strokeWidth="3.6" />
    </svg>
  );
}

function Tick() {
  return (
    <svg viewBox="0 0 48 48" fill="none" stroke="currentColor" aria-hidden="true">
      <path className="draw" d="M9 25l11 11 19-21" strokeWidth="3.6" />
    </svg>
  );
}

function Cross() {
  return (
    <svg viewBox="0 0 48 48" fill="none" stroke="currentColor" aria-hidden="true">
      <path className="draw" d="M14 14l20 20" strokeWidth="3.6" />
      <path className="draw delay" d="M34 14L14 34" strokeWidth="3.6" />
    </svg>
  );
}
