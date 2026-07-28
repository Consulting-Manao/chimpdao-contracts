import { useCallback, useEffect, useState } from "react";
import { nfcClient, type NfcStatus } from "../nfc/client.ts";

export function useNfc() {
  const [status, setStatus] = useState<NfcStatus>(nfcClient.getStatus());
  const [connected, setConnected] = useState(nfcClient.isConnected());
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const unsub = nfcClient.onStatus(setStatus);
    let cancelled = false;
    nfcClient
      .connect()
      .then(() => {
        if (!cancelled) setConnected(true);
      })
      .catch((e) => {
        if (!cancelled) {
          setConnected(false);
          setError(e instanceof Error ? e.message : String(e));
        }
      });
    const poll = setInterval(() => nfcClient.requestStatus(), 2000);
    return () => {
      cancelled = true;
      unsub();
      clearInterval(poll);
    };
  }, []);

  const retry = useCallback(async () => {
    setError(null);
    try {
      await nfcClient.connect();
      setConnected(true);
    } catch (e) {
      setConnected(false);
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  return {
    status,
    connected,
    error,
    retry,
    client: nfcClient,
  };
}
