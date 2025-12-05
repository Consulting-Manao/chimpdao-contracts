/**
 * NFC Platform Detection
 * Determines which NFC mode to use based on browser capabilities
 */

export type NFCMode = 'websocket' | 'ios-bridge' | 'none';

/**
 * Detect available NFC mode
 * - 'ios-bridge': iOS device with bridge app running (WebSocket on localhost)
 * - 'websocket': Desktop with WebSocket server + USB reader
 * - 'none': No NFC support available
 * 
 * Note: iOS bridge app must be installed and running
 */
export function detectNFCMode(): NFCMode {
  // Check if running on iOS
  if (/iPhone|iPad|iPod/.test(navigator.userAgent)) {
    // iOS devices can use bridge app (same WebSocket protocol as desktop)
    // The actual connection test happens in useNFC hook
    if (typeof WebSocket !== 'undefined') {
      return 'ios-bridge';
    }
  }
  
  // Desktop browsers will use WebSocket mode
  // (actual connection test happens in useNFC hook)
  if (typeof WebSocket !== 'undefined') {
    return 'websocket';
  }
  
  return 'none';
}

/**
 * Check if WebSocket is available
 */
export function isWebSocketAvailable(): boolean {
  return typeof WebSocket !== 'undefined';
}

/**
 * Get user-friendly platform name
 */
export function getPlatformName(mode: NFCMode): string {
  switch (mode) {
    case 'ios-bridge':
      return 'iOS Bridge App';
    case 'websocket':
      return 'Desktop USB Reader';
    case 'none':
      return 'Not Available';
  }
}

