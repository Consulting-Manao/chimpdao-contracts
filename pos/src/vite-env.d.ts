/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_NFC_WS?: string;
  readonly VITE_STELLAR_RPC?: string;
  readonly VITE_STELLAR_RPC_MAINNET?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
