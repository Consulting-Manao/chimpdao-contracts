/**
 * React hook for NFC chip operations
 * Manages connection to NFC server and provides methods for chip interaction
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { nfcClient, type NFCStatus } from '../util/nfcClient';
import type { SorobanSignature } from '../util/crypto';
import type { NFCMode } from '../util/nfcPlatform';
import { detectNFCMode, getPlatformName } from '../util/nfcPlatform';

export interface UseNFCReturn {
  // Connection state
  connected: boolean;
  chipPresent: boolean;
  readerName: string | null;
  mode: NFCMode;
  modeName: string;
  
  // Operation state
  reading: boolean;
  signing: boolean;
  
  // Error state
  error: string | null;
  
  // Last read data
  chipPublicKey: string | null;
  
  // Methods
  connect: () => Promise<void>;
  disconnect: () => void;
  readChip: () => Promise<string>;
  signWithChip: (messageDigest: Uint8Array) => Promise<SorobanSignature>;
  clearError: () => void;
}

export function useNFC(): UseNFCReturn {
  const [connected, setConnected] = useState(false);
  const [mode, setMode] = useState<NFCMode>('none');
  const [status, setStatus] = useState<NFCStatus>({
    readerConnected: false,
    chipPresent: false,
    readerName: null
  });
  const [reading, setReading] = useState(false);
  const [signing, setSigning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [chipPublicKey, setChipPublicKey] = useState<string | null>(null);
  
  const connectingRef = useRef(false);

  // Detect mode on mount
  useEffect(() => {
    const detectedMode = detectNFCMode();
    setMode(detectedMode);
  }, []);

  // Auto-connect on mount
  useEffect(() => {
    if (!connectingRef.current && !connected) {
      connectingRef.current = true;
      nfcClient.connect()
        .then(() => {
          setConnected(true);
          setError(null);
        })
        .catch((err) => {
          const message = err instanceof Error ? err.message : 'Connection failed';
          setError(`Failed to connect: ${message}`);
        })
        .finally(() => {
          connectingRef.current = false;
        });
    }

    // Set up event listeners
    const handleEvent = (event: { type: string; data?: unknown }) => {
      switch (event.type) {
        case 'connected':
          setConnected(true);
          setError(null);
          break;

        case 'disconnected':
          setConnected(false);
          setStatus({
            readerConnected: false,
            chipPresent: false,
            readerName: null
          });
          break;

        case 'status':
          setStatus(event.data as NFCStatus);
          break;

        case 'error':
          setError(event.data as string);
          break;
      }
    };

    nfcClient.addListener(handleEvent);

    return () => {
      nfcClient.removeListener(handleEvent);
    };
  }, [connected]);

  const connect = useCallback(async () => {
    try {
      setError(null);
      await nfcClient.connect();
      setConnected(true);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Connection failed';
      setError(message);
      throw err;
    }
  }, []);

  const disconnect = useCallback(() => {
    nfcClient.disconnect();
    setConnected(false);
    setStatus({
      readerConnected: false,
      chipPresent: false,
      readerName: null
    });
  }, []);

  const readChip = useCallback(async (): Promise<string> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    if (!status.chipPresent) {
      throw new Error('No chip present. Please place chip on reader.');
    }

    setReading(true);
    setError(null);

    try {
      const publicKey = await nfcClient.readPublicKey();
      setChipPublicKey(publicKey);
      return publicKey;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to read chip';
      setError(message);
      throw err;
    } finally {
      setReading(false);
    }
  }, [connected, status.chipPresent]);

  const signWithChip = useCallback(async (messageDigest: Uint8Array): Promise<SorobanSignature> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    if (!status.chipPresent) {
      throw new Error('No chip present. Please place chip on reader.');
    }

    setSigning(true);
    setError(null);

    try {
      const signature = await nfcClient.signMessage(messageDigest);
      return signature;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to sign with chip';
      setError(message);
      throw err;
    } finally {
      setSigning(false);
    }
  }, [connected, status.chipPresent]);

  const clearError = useCallback(() => {
    setError(null);
  }, []);

  return {
    connected,
    chipPresent: status.chipPresent,
    readerName: status.readerName,
    mode,
    modeName: getPlatformName(mode),
    reading,
    signing,
    error,
    chipPublicKey,
    connect,
    disconnect,
    readChip,
    signWithChip,
    clearError
  };
}

