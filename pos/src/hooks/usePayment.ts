import { useCallback, useEffect, useRef, useState } from "react";
import type { Asset } from "../chain/assets.ts";
import type { PaymentChain, PaymentResult } from "../chain/types.ts";
import { approvedBeep, cardBeep, declinedBeep } from "../lib/beep.ts";
import { addPayments, recordFor } from "../lib/history.ts";
import type { NfcClient } from "../nfc/client.ts";

export type PayPhase = "idle" | "waiting" | "paying" | "done";

/** Where in the tap we are: the card only has to stay on the reader up to `sign`. */
export type PayStep = "tap" | "sign" | "submit";

export const SUCCESS_HOLD_MS = 8000;

/** A customer needs time to find their wallet and get the card out. */
export const TAP_WINDOW_MS = 60_000;

/**
 * The card never answered, so nothing was charged and another tap may well
 * work. Anything else (unfunded card, dead network) is a real decline.
 */
const BAD_TAP =
  /transmit|SELECT|public key|sign message|signature|card was removed|card state cleared|chip on the reader/i;

// ponytail: assert a flaky reader retaps while a broke card declines
if (import.meta.env.DEV) {
  const retryable = [
    "Failed to read public key: Failed to transmit SELECT command: An error occurred while transmitting.",
    "Place the chip on the reader",
  ];
  const declines = ["tecUNFUNDED_PAYMENT", "No card tapped", "Account not found"];
  for (const m of retryable) {
    if (!BAD_TAP.test(m)) console.warn("should retap:", m);
  }
  for (const m of declines) {
    if (BAD_TAP.test(m)) console.warn("should decline:", m);
  }
}

export function usePayment(
  nfc: NfcClient,
  chipPresent: boolean,
  chain: PaymentChain,
  asset: Asset,
  destination: string,
) {
  const [amount, setAmount] = useState("0");
  const [phase, setPhase] = useState<PayPhase>("idle");
  const [step, setStep] = useState<PayStep>("tap");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<PaymentResult | null>(null);
  const busy = useRef(false);
  // A misread must not re-fire while the same card still sits on the reader.
  const needFreshTap = useRef(false);
  // Absolute, so retapping after a misread can't keep the terminal armed forever.
  const tapDeadline = useRef(0);

  const ready =
    phase === "idle" && Number(amount) > 0 && chain.isAddress(destination);

  const arm = useCallback(() => {
    busy.current = false;
    needFreshTap.current = false;
    tapDeadline.current = Date.now() + TAP_WINDOW_MS;
    setError(null);
    setResult(null);
    setStep("tap");
    setPhase("waiting");
    chain.warmUp?.();
  }, [chain]);

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
    setError(null);
    setPhase("paying");
    setStep("sign");
    cardBeep();
    let signed = false;
    try {
      const res = await chain.pay(
        { amount, asset, destination },
        {
          readPublicKey: () => nfc.readPublicKey(),
          signDigest: async (d) => {
            const sig = await nfc.signDigest(d);
            signed = true;
            setStep("submit"); // signature captured, the card is free now
            return sig;
          },
        },
      );
      setResult(res);
      addPayments([recordFor(chain, asset, res, destination)]);
      approvedBeep();
      setPhase("done");
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
      // A real terminal asks for another tap instead of declining a misread.
      if (!signed && BAD_TAP.test(msg)) {
        needFreshTap.current = true;
        setStep("tap");
        setPhase("waiting");
      } else {
        declinedBeep();
        setPhase("done");
      }
    } finally {
      busy.current = false;
    }
  }, [amount, asset, chain, destination, nfc]);

  // Chip landing on the reader is what triggers the payment.
  useEffect(() => {
    if (phase !== "waiting" || busy.current) return;
    if (!chipPresent) {
      needFreshTap.current = false; // lifted, so the next landing is a new tap
      return;
    }
    if (needFreshTap.current) return;
    void run();
  }, [phase, chipPresent, run]);

  // Don't sit armed forever if nobody taps.
  useEffect(() => {
    if (phase !== "waiting") return;
    const t = setTimeout(
      () => {
        setError("No card tapped");
        setPhase("done");
      },
      Math.max(0, tapDeadline.current - Date.now()),
    );
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
  };
}
