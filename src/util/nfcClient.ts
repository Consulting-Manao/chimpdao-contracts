/**
 * NFC Client for Desktop (WebSocket + USB reader)
 * Desktop-only implementation using WebSocket server
 */

import type { NFCSignature, SorobanSignature } from './crypto';
import { formatSignatureForSoroban, bytesToHex } from './crypto';

/**
 * WebSocket URL for NFC server (desktop only)
 */
const WEBSOCKET_URL = 'ws://localhost:8080';

export interface NFCStatus {
  readerConnected: boolean;
  chipPresent: boolean;
  readerName: string | null;
}

export type NFCClientEventType = 'status' | 'error' | 'connected' | 'disconnected';

export interface NFCClientEvent {
  type: NFCClientEventType;
  data?: NFCStatus | string;
}

export type NFCClientEventListener = (event: NFCClientEvent) => void;

/**
 * Custom error types for better error handling
 */
export class NFCServerNotRunningError extends Error {
  constructor(message = 'NFC server is not running. Please start it with: bun run nfc-server') {
    super(message);
    this.name = 'NFCServerNotRunningError';
  }
}

export class ChipNotPresentError extends Error {
  constructor(message = 'No NFC chip detected. Please place the chip on the reader.') {
    super(message);
    this.name = 'ChipNotPresentError';
  }
}

export class APDUCommandFailedError extends Error {
  constructor(message = 'APDU command failed. The chip may not be properly positioned or compatible.') {
    super(message);
    this.name = 'APDUCommandFailedError';
  }
}

export class RecoveryIdError extends Error {
  constructor(message = 'Could not determine recovery ID. This may indicate a signature mismatch.') {
    super(message);
    this.name = 'RecoveryIdError';
  }
}

interface WebSocketMessage {
  type: string;
  success?: boolean;
  data?: {
    publicKey?: string;
    signature?: string;
    r?: string;
    s?: string;
    recoveryId?: number;
    readerConnected?: boolean;
    chipPresent?: boolean;
    readerName?: string | null;
    url?: string | null;
    message?: string;
    [key: string]: unknown;
  };
  error?: string;
}

/**
 * WebSocket-based NFC Client for Desktop USB readers
 */
class WebSocketNFCClient {
  private ws: WebSocket | null = null;
  private wsUrl: string;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 2000;
  private listeners: Set<NFCClientEventListener> = new Set();
  private currentStatus: NFCStatus = {
    readerConnected: false,
    chipPresent: false,
    readerName: null
  };

  constructor(wsUrl?: string) {
    this.wsUrl = wsUrl || WEBSOCKET_URL;
  }

  /**
   * Connect to NFC WebSocket server
   */
  async connect(): Promise<void> {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      return; // Already connected
    }

    return new Promise((resolve, reject) => {
      try {
        this.ws = new WebSocket(this.wsUrl);

        this.ws.onopen = () => {
          this.reconnectAttempts = 0;
          this.emit({ type: 'connected' });
          
          // Request initial status
          this.requestStatus();
          resolve();
        };

        this.ws.onmessage = (event) => {
          try {
            const message = JSON.parse(event.data as string) as WebSocketMessage;
            this.handleMessage(message);
          } catch (error) {
            console.error('Failed to parse WebSocket message:', error);
          }
        };

        this.ws.onerror = (event) => {
          console.error('WebSocket error:', event);
        };

        this.ws.onclose = (event) => {
          this.emit({ type: 'disconnected' });
          this.currentStatus = {
            readerConnected: false,
            chipPresent: false,
            readerName: null
          };
          
          // Log close details for debugging
          console.log('WebSocket closed:', { code: event.code, reason: event.reason, wasClean: event.wasClean });
          
          // If connection closed during initial connect attempt and not normal closure, reject
          if (event.code !== 1000 && event.code !== 1001) {
            const errorMsg = this.getConnectionErrorMessage(event.code, event.reason);
            reject(new NFCServerNotRunningError(errorMsg));
            return;
          }
          
          // Attempt reconnection if not manually disconnected
          if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            setTimeout(() => {
              this.connect().catch(() => {
                // Reconnection failed, will try again
              });
            }, this.reconnectDelay);
          } else {
            const errorMsg = this.getConnectionErrorMessage();
            reject(new NFCServerNotRunningError(errorMsg));
          }
        };
      } catch (error) {
        reject(error instanceof Error ? error : new Error('Unknown connection error'));
      }
    });
  }

  /**
   * Disconnect from NFC server
   */
  disconnect(): void {
    if (this.ws) {
      this.reconnectAttempts = this.maxReconnectAttempts; // Prevent auto-reconnect
      this.ws.close();
      this.ws = null;
    }
  }

  /**
   * Check if connected to NFC server
   */
  isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  /**
   * Get current NFC status
   */
  getStatus(): NFCStatus {
    return { ...this.currentStatus };
  }

  /**
   * Request status update from server
   */
  requestStatus(): void {
    if (!this.isConnected()) {
      return; // Silently return if not connected
    }
    this.send({ type: 'status' });
  }

  /**
   * Read public key from NFC chip
   */
  async readPublicKey(): Promise<string> {
    return new Promise((resolve, reject) => {
      if (!this.isConnected()) {
        reject(new Error('Not connected to NFC server'));
        return;
      }

      if (!this.currentStatus.chipPresent) {
        reject(new ChipNotPresentError());
        return;
      }

      const handler = (event: NFCClientEvent) => {
        if (event.type === 'error') {
          this.removeListener(handler);
          reject(new Error(event.data as string));
        }
      };

      this.addListener(handler);

      // Send request
      this.send({ type: 'read-pubkey' });

      // Set up one-time message listener
      const messageHandler = (event: MessageEvent) => {
        try {
          const message = JSON.parse(event.data as string) as WebSocketMessage;
          if (message.type === 'pubkey' && message.success && message.data?.publicKey) {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            resolve(message.data.publicKey);
          } else if (message.type === 'error') {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            reject(new Error(message.error ?? 'Unknown error'));
          }
        } catch {
          // Ignore parse errors
        }
      };

      if (this.ws) {
        this.ws.addEventListener('message', messageHandler);
      }

      // Timeout after 10 seconds
      setTimeout(() => {
        this.removeListener(handler);
        if (this.ws) {
          this.ws.removeEventListener('message', messageHandler);
        }
        reject(new Error('Timeout reading public key'));
      }, 10000);
    });
  }

  /**
   * Sign message with NFC chip
   * Returns signature in Soroban format (64-byte signature + recovery_id)
   */
  async signMessage(messageDigest: Uint8Array): Promise<SorobanSignature> {
    return new Promise((resolve, reject) => {
      if (!this.isConnected()) {
        reject(new Error('Not connected to NFC server'));
        return;
      }

      if (!this.currentStatus.chipPresent) {
        reject(new ChipNotPresentError());
        return;
      }

      if (messageDigest.length !== 32) {
        reject(new Error('Message digest must be exactly 32 bytes'));
        return;
      }

      const handler = (event: NFCClientEvent) => {
        if (event.type === 'error') {
          this.removeListener(handler);
          reject(new Error(event.data as string));
        }
      };

      this.addListener(handler);

      // Convert message digest to hex
      const messageDigestHex = bytesToHex(messageDigest);

      // Send sign request
      this.send({
        type: 'sign',
        data: { messageDigest: messageDigestHex }
      });

      // Set up one-time message listener
      const messageHandler = (event: MessageEvent) => {
        try {
          const message = JSON.parse(event.data as string) as WebSocketMessage;
          if (message.type === 'signature' && message.success && message.data) {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            
            // Debug logging
            console.log('Received signature from server:', {
              r: message.data.r?.substring(0, 20) + '...',
              s: message.data.s?.substring(0, 20) + '...',
              rLength: message.data.r?.length,
              sLength: message.data.s?.length,
              recoveryId: message.data.recoveryId,
              v: message.data.v
            });
            
            // Convert to Soroban format
            // If server provided recoveryId, use it; otherwise formatSignatureForSoroban will try to determine it
            const recoveryIdFromServer = message.data.recoveryId as number | undefined;
            const nfcSig: NFCSignature = {
              r: message.data.r ?? '',
              s: message.data.s ?? '',
              v: recoveryIdFromServer !== undefined ? recoveryIdFromServer : 0, // v is required by interface
              recoveryId: recoveryIdFromServer
            };
            
            try {
              const sorobanSig = formatSignatureForSoroban(nfcSig);
              console.log('Formatted signature for Soroban:', {
                signatureLength: sorobanSig.signatureBytes.length,
                recoveryId: sorobanSig.recoveryId
              });
              resolve(sorobanSig);
            } catch (formatError) {
              console.error('Failed to format signature:', formatError);
              reject(formatError instanceof Error ? formatError : new Error('Failed to format signature'));
            }
          } else if (message.type === 'error') {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            reject(new Error(message.error ?? 'Unknown error'));
          }
        } catch {
          // Ignore parse errors
        }
      };

      if (this.ws) {
        this.ws.addEventListener('message', messageHandler);
      }

      // Timeout after 30 seconds (chip signing can take a while)
      setTimeout(() => {
        this.removeListener(handler);
        if (this.ws) {
          this.ws.removeEventListener('message', messageHandler);
        }
        reject(new Error('Timeout signing message'));
      }, 30000);
    });
  }

  /**
   * Read NDEF data from NFC chip
   */
  async readNDEF(): Promise<string | null> {
    return new Promise((resolve, reject) => {
      if (!this.isConnected()) {
        reject(new Error('Not connected to NFC server'));
        return;
      }

      if (!this.currentStatus.chipPresent) {
        reject(new ChipNotPresentError());
        return;
      }

      const handler = (event: NFCClientEvent) => {
        if (event.type === 'error') {
          this.removeListener(handler);
          reject(new Error(event.data as string));
        }
      };

      this.addListener(handler);

      // Send read NDEF request
      this.send({ type: 'read-ndef' });

      // Set up one-time message listener
      const messageHandler = (event: MessageEvent) => {
        try {
          const message = JSON.parse(event.data as string) as WebSocketMessage;
          if (message.type === 'ndef-read' && message.success) {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            resolve(message.data?.url || null);
          } else if (message.type === 'error') {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            reject(new Error(message.error ?? 'Unknown error'));
          }
        } catch {
          // Ignore parse errors
        }
      };

      if (this.ws) {
        this.ws.addEventListener('message', messageHandler);
      }

      // Timeout after 10 seconds
      setTimeout(() => {
        this.removeListener(handler);
        if (this.ws) {
          this.ws.removeEventListener('message', messageHandler);
        }
        reject(new Error('Timeout reading NDEF'));
      }, 10000);
    });
  }

  /**
   * Write NDEF URL record to NFC chip
   */
  async writeNDEF(url: string): Promise<string> {
    return new Promise((resolve, reject) => {
      if (!this.isConnected()) {
        reject(new Error('Not connected to NFC server'));
        return;
      }

      if (!this.currentStatus.chipPresent) {
        reject(new ChipNotPresentError());
        return;
      }

      const handler = (event: NFCClientEvent) => {
        if (event.type === 'error') {
          this.removeListener(handler);
          reject(new Error(event.data as string));
        }
      };

      this.addListener(handler);

      // Send write NDEF request
      this.send({
        type: 'write-ndef',
        data: { url }
      });

      // Set up one-time message listener
      const messageHandler = (event: MessageEvent) => {
        try {
          const message = JSON.parse(event.data as string) as WebSocketMessage;
          if (message.type === 'ndef-written' && message.success && message.data?.url) {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            resolve(message.data.url);
          } else if (message.type === 'error') {
            this.removeListener(handler);
            if (this.ws) {
              this.ws.removeEventListener('message', messageHandler);
            }
            reject(new Error(message.error ?? 'Unknown error'));
          }
        } catch {
          // Ignore parse errors
        }
      };

      if (this.ws) {
        this.ws.addEventListener('message', messageHandler);
      }

      // Timeout after 10 seconds
      setTimeout(() => {
        this.removeListener(handler);
        if (this.ws) {
          this.ws.removeEventListener('message', messageHandler);
        }
        reject(new Error('Timeout writing NDEF'));
      }, 10000);
    });
  }

  /**
   * Add event listener
   */
  addListener(listener: NFCClientEventListener): void {
    this.listeners.add(listener);
  }

  /**
   * Remove event listener
   */
  removeListener(listener: NFCClientEventListener): void {
    this.listeners.delete(listener);
  }

  /**
   * Get user-friendly connection error message (desktop only)
   */
  private getConnectionErrorMessage(code?: number, _reason?: string): string {
    return `NFC server connection failed (code: ${code || 'unknown'}). ` +
      'Start the NFC server with: bun run nfc-server';
  }

  /**
   * Send message to server
   */
  private send(message: Record<string, unknown>): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    } else {
      throw new Error('WebSocket not connected');
    }
  }

  /**
   * Handle incoming message from server
   */
  private handleMessage(message: WebSocketMessage): void {
    switch (message.type) {
      case 'status':
        if (message.data) {
          const data = message.data;
          this.currentStatus = {
            readerConnected: Boolean(data.readerConnected),
            chipPresent: Boolean(data.chipPresent),
            readerName: typeof data.readerName === 'string' || data.readerName === null ? data.readerName : null
          };
          this.emit({ type: 'status', data: this.currentStatus });
        }
        break;

      case 'error':
        this.emit({ type: 'error', data: message.error ?? 'Unknown error' });
        break;

      default:
        // Other message types are handled by specific request handlers
        break;
    }
  }

  /**
   * Emit event to all listeners
   */
  private emit(event: NFCClientEvent): void {
    this.listeners.forEach(listener => {
      try {
        listener(event);
      } catch (error) {
        console.error('Error in event listener:', error);
      }
    });
  }
}

/**
 * NFC Client (Desktop only - WebSocket)
 */
export class NFCClient {
  private wsClient?: WebSocketNFCClient;
  private listeners: Set<NFCClientEventListener> = new Set();

  /**
   * Connect to NFC interface
   */
  async connect(): Promise<void> {
    this.wsClient = new WebSocketNFCClient();
    await this.wsClient.connect();
  }

  /**
   * Disconnect from NFC interface
   */
  disconnect(): void {
    if (this.wsClient) {
      this.wsClient.disconnect();
      this.wsClient = undefined;
    }
    this.emit({ type: 'disconnected' });
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    if (this.wsClient) {
      return this.wsClient.isConnected();
    }
    return false;
  }

  /**
   * Get status
   */
  getStatus(): NFCStatus {
    if (this.wsClient) {
      return this.wsClient.getStatus();
    }
    
    return {
      readerConnected: false,
      chipPresent: false,
      readerName: null
    };
  }

  /**
   * Request status update from server
   */
  requestStatus(): void {
    if (this.wsClient && this.isConnected()) {
      this.wsClient.requestStatus();
    }
  }

  /**
   * Read public key from chip
   */
  async readPublicKey(): Promise<string> {
    if (this.wsClient) {
      return await this.wsClient.readPublicKey();
    }
    throw new Error('Not connected');
  }

  /**
   * Sign message with chip
   */
  async signMessage(messageDigest: Uint8Array): Promise<SorobanSignature> {
    if (this.wsClient) {
      return await this.wsClient.signMessage(messageDigest);
    }
    throw new Error('Not connected');
  }

  /**
   * Read NDEF data from chip
   */
  async readNDEF(): Promise<string | null> {
    if (this.wsClient) {
      return await this.wsClient.readNDEF();
    }
    throw new Error('Not connected');
  }

  /**
   * Write NDEF URL to chip
   */
  async writeNDEF(url: string): Promise<string> {
    if (this.wsClient) {
      return await this.wsClient.writeNDEF(url);
    }
    throw new Error('Not connected');
  }

  /**
   * Add event listener
   */
  addListener(listener: NFCClientEventListener): void {
    this.listeners.add(listener);
    if (this.wsClient) {
      this.wsClient.addListener(listener);
    }
  }

  /**
   * Remove event listener
   */
  removeListener(listener: NFCClientEventListener): void {
    this.listeners.delete(listener);
    if (this.wsClient) {
      this.wsClient.removeListener(listener);
    }
  }

  /**
   * Emit event
   */
  private emit(event: NFCClientEvent): void {
    this.listeners.forEach(listener => {
      try {
        listener(event);
      } catch (error) {
        console.error('Error in event listener:', error);
      }
    });
  }
}

// Export singleton instance
export const nfcClient = new NFCClient();

