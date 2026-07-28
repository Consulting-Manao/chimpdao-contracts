/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_CHAIN?: string;
  readonly VITE_XRPL_WS?: string;
  readonly VITE_NFC_WS?: string;
  readonly VITE_MERCHANT_ADDRESS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
