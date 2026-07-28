import type {
  PaymentChain,
  PaymentRecord,
  PaymentResult,
} from "../chain/types.ts";

const KEY = "chimp.payments.v1";

// ponytail: newest-first array in localStorage, capped. Ceiling is the ~5 MB
// origin quota and a full rewrite per sale; move to IndexedDB if history ever
// needs paging or per-chain queries.
const MAX = 200;

/** Local sales and, later, RPC-pulled transactions both land here. */
export function mergeRecords(
  existing: PaymentRecord[],
  incoming: PaymentRecord[],
): PaymentRecord[] {
  const byId = new Map(existing.map((r) => [r.id, r]));
  for (const r of incoming) byId.set(r.id, r); // a fresher source wins
  return [...byId.values()].sort((a, b) => b.at - a.at).slice(0, MAX);
}

function isRecord(v: unknown): v is PaymentRecord {
  const r = v as PaymentRecord;
  return (
    !!r &&
    typeof r.id === "string" &&
    typeof r.chain === "string" &&
    typeof r.amount === "string" &&
    typeof r.symbol === "string" &&
    typeof r.at === "number"
  );
}

export function listPayments(): PaymentRecord[] {
  try {
    const raw: unknown = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    return Array.isArray(raw) ? raw.filter(isRecord) : [];
  } catch {
    return []; // corrupt or unavailable storage must not break the terminal
  }
}

export function addPayments(incoming: PaymentRecord[]): PaymentRecord[] {
  const next = mergeRecords(listPayments(), incoming);
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    /* a sale that can't be logged still went through */
  }
  return next;
}

export function clearPayments(): void {
  localStorage.removeItem(KEY);
}

export function recordFor(
  chain: PaymentChain,
  res: PaymentResult,
  to: string,
): PaymentRecord {
  return {
    id: `${chain.id}:${res.hash}`,
    chain: chain.id,
    hash: res.hash,
    from: res.from,
    to,
    amount: res.amount,
    symbol: res.symbol,
    at: Date.now(),
    explorerUrl: res.explorerUrl,
  };
}

// ponytail: assert the merge dedupes by id and keeps newest first
if (import.meta.env.DEV) {
  const at = (id: string, t: number) =>
    ({ id, at: t, chain: "x", amount: "1", symbol: "X" }) as PaymentRecord;
  const merged = mergeRecords([at("a", 1)], [at("a", 9), at("b", 5)]);
  if (merged.length !== 2 || merged[0]?.id !== "a" || merged[0]?.at !== 9) {
    console.warn("history self-check failed", merged);
  }
}
