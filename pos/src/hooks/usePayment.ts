import { useCallback, useEffect, useRef, useState } from "react";
import { activeChain, type PaymentResult } from "../chain/index.ts";
import { approvedBeep, cardBeep, declinedBeep } from "../lib/beep.ts";
import { addPayments, recordFor } from "../lib/history.ts";
import type { NfcClient } from "../nfc/client.ts";

export type PayPhase = "idle" | "waiting" | "paying" | "done";

/** Where in the tap we are: the card only has to stay on the reader up to `sign`. */
export type PayStep = "tap" | "sign" | "submit";

export const SUCCESS_HOLD_MS = 8000;

/** A customer needs time to find their wallet and get the card out. */
export const TAP_WINDOW_MS = 60_000;

export function usePayment(
  nfc: NfcClient,
  chipPresent: boolean,
  destination: string,
) {
  const [amount, setAmount] = useState("0");
  const [phase, setPhase] = useState<PayPhase>("idle");
  const [step, setStep] = useState<PayStep>("tap");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<PaymentResult | null>(null);
  const busy = useRef(false);

  const ready =
    phase === "idle" && Number(amount) > 0 && destination.startsWith("r");

  const arm = useCallback(() => {
    busy.current = false;
    setError(null);
    setResult(null);
    setStep("tap");
    setPhase("waiting");
    activeChain.warmUp?.();
  }, []);

  const start = useCallback(() => {
    if (ready) arm();
  }, [ready, arm]);

  /** A decline should be re-tappable, so retry goes back to waiting for a card. */
  const retry = useCallback(() => {
    if (phase === "done") arm();
  }, [phase, arm]);

  // Cancelling keeps the amount so the cashier can retry; a finished sale clears it.
  const reset = useCallback(() => {
    busy.current = false;
    if (phase === "done") setAmount("0");
    setPhase("idle");
    setStep("tap");
    setError(null);
    setResult(null);
  }, [phase]);

  const run = useCallback(async () => {
    busy.current = true;
    setPhase("paying");
    setStep("sign");
    cardBeep();
    try {
      const res = await activeChain.pay(
        { amount, destination },
        {
          readPublicKey: () => nfc.readPublicKey(),
          signDigest: async (d) => {
            const sig = await nfc.signDigest(d);
            setStep("submit"); // signature captured, the card is free now
            return sig;
          },
        },
      );
      setResult(res);
      addPayments([recordFor(activeChain, res, destination)]);
      approvedBeep();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      declinedBeep();
    } finally {
      busy.current = false;
      setPhase("done");
    }
  }, [amount, destination, nfc]);

  // Chip landing on the reader is what triggers the payment.
  useEffect(() => {
    if (phase !== "waiting" || !chipPresent || busy.current) return;
    void run();
  }, [phase, chipPresent, run]);

  // Don't sit armed forever if nobody taps.
  useEffect(() => {
    if (phase !== "waiting") return;
    const t = setTimeout(() => {
      setError("No card tapped");
      setPhase("done");
    }, TAP_WINDOW_MS);
    return () => clearTimeout(t);
  }, [phase]);

  // A real terminal goes back to idle on its own; a decline waits to be read.
  useEffect(() => {
    if (phase !== "done" || error) return;
    const t = setTimeout(reset, SUCCESS_HOLD_MS);
    return () => clearTimeout(t);
  }, [phase, error, reset]);

  return {
    amount,
    setAmount,
    phase,
    step,
    error,
    result,
    ready,
    start,
    retry,
    reset,
    symbol: activeChain.symbol,
  };
}
