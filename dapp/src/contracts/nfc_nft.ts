import * as Client from "nfc_nft";
import { rpcUrl } from "./util.ts";

export default new Client.Client({
  networkPassphrase: "Standalone Network ; February 2017",
  contractId: "CAJAVOKQZG5ZHQFHNKJC6ZBSRNNJFVEUOPS6P6SFQR4XZC55YLBX4VZL",
  rpcUrl,
  allowHttp: true,
  publicKey: undefined,
});
