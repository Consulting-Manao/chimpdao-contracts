/**
 * Unified NFC Client
 * Supports Desktop (WebSocket + USB reader)
 * 
 * Note: Android support will be added via bridge app in the future
 */

import type { NFCSignature, SorobanSignature } from './crypto';
import { formatSignatureForSoroban, bytesToHex } from './crypto';
import { detectNFCMode, type NFCMode } from './nfcPlatform';

const DEFAULT_WS_URL = 'ws://localhost:8080';

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
    this.wsUrl = wsUrl || DEFAULT_WS_URL;
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

        this.ws.onerror = () => {
          console.error('WebSocket error');
          this.emit({ type: 'error', data: 'WebSocket connection error' });
          reject(new NFCServerNotRunningError());
        };

        this.ws.onclose = () => {
          this.emit({ type: 'disconnected' });
          this.currentStatus = {
            readerConnected: false,
            chipPresent: false,
            readerName: null
          };
          
          // Attempt reconnection
          if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            setTimeout(() => {
              this.connect().catch(() => {
                // Reconnection failed, will try again
              });
            }, this.reconnectDelay);
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
            
            // Convert to Soroban format
            // If server provided recoveryId, use it; otherwise formatSignatureForSoroban will try to determine it
            const recoveryIdFromServer = message.data.recoveryId as number | undefined;
            const nfcSig: NFCSignature = {
              r: message.data.r ?? '',
              s: message.data.s ?? '',
              v: recoveryIdFromServer !== undefined ? recoveryIdFromServer : 0, // v is required by interface
              recoveryId: recoveryIdFromServer
            };
            const sorobanSig = formatSignatureForSoroban(nfcSig);
            resolve(sorobanSig);
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
 * Unified NFC Client
 * Currently supports WebSocket mode only (Desktop)
 */
export class UnifiedNFCClient {
  private mode: NFCMode = 'none';
  private wsClient?: WebSocketNFCClient;
  private listeners: Set<NFCClientEventListener> = new Set();

  /**
   * Connect to NFC interface
   */
  async connect(): Promise<void> {
    this.mode = detectNFCMode();
    
    if (this.mode === 'websocket' || this.mode === 'ios-bridge') {
      // Both desktop and iOS bridge use WebSocket on localhost:8080
      this.wsClient = new WebSocketNFCClient();
      await this.wsClient.connect();
      // WebSocket client emits its own connected event
    } else {
      throw new NFCServerNotRunningError('No NFC support available. WebSocket is required for NFC operations.');
    }
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
   * Get current mode
   */
  getMode(): NFCMode {
    return this.mode;
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

// Export singleton instance with unified interface
export const nfcClient = new UnifiedNFCClient();

