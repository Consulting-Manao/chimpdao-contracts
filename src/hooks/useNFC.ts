/**
 * React hook for NFC chip operations
 * Manages connection to NFC server and provides methods for chip interaction
 */

import { useState, useEffect, useCallback } from 'react';
import { nfcClient } from '../util/nfcClient';
import type { SorobanSignature } from '../util/crypto';
import type { KeyInfo } from '../util/nfcClient';

export interface UseNFCReturn {
  // Connection state
  connected: boolean;
  
  // Operation state
  signing: boolean;
  readingNDEF: boolean;
  writingNDEF: boolean;
  generatingKey: boolean;
  fetchingKey: boolean;
  
  // Methods
  connect: () => Promise<void>;
  readChip: (keyId?: number) => Promise<string>;
  signWithChip: (messageDigest: Uint8Array, keyId?: number) => Promise<SorobanSignature>;
  readNDEF: () => Promise<string | null>;
  writeNDEF: (url: string) => Promise<string>;
  generateKey: () => Promise<KeyInfo>;
  fetchKeyById: (keyId: number) => Promise<KeyInfo>;
}

export function useNFC(): UseNFCReturn {
  const [connected, setConnected] = useState(false);
  const [signing, setSigning] = useState(false);
  const [readingNDEF, setReadingNDEF] = useState(false);
  const [writingNDEF, setWritingNDEF] = useState(false);
  const [generatingKey, setGeneratingKey] = useState(false);
  const [fetchingKey, setFetchingKey] = useState(false);

  // Set up event listeners for connection state
  useEffect(() => {
    const handleEvent = (event: { type: string; data?: unknown }) => {
      switch (event.type) {
        case 'connected':
          setConnected(true);
          break;

        case 'disconnected':
          setConnected(false);
          break;
      }
    };

    nfcClient.addListener(handleEvent);

    return () => {
      nfcClient.removeListener(handleEvent);
    };
  }, []);


  const connect = useCallback(async () => {
    await nfcClient.connect();
    setConnected(true);
  }, []);

  const readChip = useCallback(async (keyId?: number): Promise<string> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    // Let the server handle chip presence checking - it will throw an error if chip not present
    return await nfcClient.readPublicKey(keyId);
  }, [connected]);

  const signWithChip = useCallback(async (messageDigest: Uint8Array, keyId?: number): Promise<SorobanSignature> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    setSigning(true);
    try {
      // Let the server handle chip presence checking - it will throw an error if chip not present
      return await nfcClient.signMessage(messageDigest, keyId);
    } finally {
      setSigning(false);
    }
  }, [connected]);

  const readNDEF = useCallback(async (): Promise<string | null> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    setReadingNDEF(true);
    try {
      return await nfcClient.readNDEF();
    } finally {
      setReadingNDEF(false);
    }
  }, [connected]);

  const writeNDEF = useCallback(async (url: string): Promise<string> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    setWritingNDEF(true);
    try {
      return await nfcClient.writeNDEF(url);
    } finally {
      setWritingNDEF(false);
    }
  }, [connected]);

  const generateKey = useCallback(async (): Promise<KeyInfo> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    setGeneratingKey(true);
    try {
      return await nfcClient.generateKey();
    } finally {
      setGeneratingKey(false);
    }
  }, [connected]);

  const fetchKeyById = useCallback(async (keyId: number): Promise<KeyInfo> => {
    if (!connected) {
      throw new Error('Not connected to NFC server');
    }

    setFetchingKey(true);
    try {
      return await nfcClient.fetchKeyById(keyId);
    } finally {
      setFetchingKey(false);
    }
  }, [connected]);

  return {
    connected,
    signing,
    readingNDEF,
    writingNDEF,
    generatingKey,
    fetchingKey,
    connect,
    readChip,
    signWithChip,
    readNDEF,
    writeNDEF,
    generateKey,
    fetchKeyById
  };
}

