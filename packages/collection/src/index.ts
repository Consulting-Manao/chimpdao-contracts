import { Buffer } from "buffer";
import { Address } from "@stellar/stellar-sdk";
import {
  AssembledTransaction,
  Client as ContractClient,
  ClientOptions as ContractClientOptions,
  MethodOptions,
  Result,
  Spec as ContractSpec,
} from "@stellar/stellar-sdk/contract";
import type {
  u32,
  i32,
  u64,
  i64,
  u128,
  i128,
  u256,
  i256,
  Option,
  Timepoint,
  Duration,
} from "@stellar/stellar-sdk/contract";
export * from "@stellar/stellar-sdk";
export * as contract from "@stellar/stellar-sdk/contract";
export * as rpc from "@stellar/stellar-sdk/rpc";

if (typeof window !== "undefined") {
  //@ts-ignore Buffer exists
  window.Buffer = window.Buffer || Buffer;
}

export type DataKey = { tag: "Admin"; values: void };

export type CollectionKey = { tag: "NFTContract"; values: void };

export const CollectionError = {
  /**
   * Indicates a non-existent `token_id`.
   */
  300: { message: "NonExistentCollection" },
};

export interface Client {
  /**
   * Construct and simulate a upgrade transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  upgrade: (
    { wasm_hash }: { wasm_hash: Buffer },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<null>>;
}
export class Client extends ContractClient {
  static async deploy<T = Client>(
    /** Constructor/Initialization Args for the contract's `__constructor` method */
    { admin }: { admin: string },
    /** Options for initializing a Client as well as for calling a method, with extras specific to deploying. */
    options: MethodOptions &
      Omit<ContractClientOptions, "contractId"> & {
        /** The hash of the Wasm blob, which must already be installed on-chain. */
        wasmHash: Buffer | string;
        /** Salt used to generate the contract's ID. Passed through to {@link Operation.createCustomContract}. Default: random. */
        salt?: Buffer | Uint8Array;
        /** The format used to decode `wasmHash`, if it's provided as a string. */
        format?: "hex" | "base64";
      },
  ): Promise<AssembledTransaction<T>> {
    return ContractClient.deploy({ admin }, options);
  }
  constructor(public readonly options: ContractClientOptions) {
    super(
      new ContractSpec([
        "AAAAAgAAAAAAAAAAAAAAB0RhdGFLZXkAAAAAAQAAAAAAAAAAAAAABUFkbWluAAAA",
        "AAAAAgAAAAAAAAAAAAAADUNvbGxlY3Rpb25LZXkAAAAAAAABAAAAAAAAAAAAAAALTkZUQ29udHJhY3QA",
        "AAAAAAAAAAAAAAANX19jb25zdHJ1Y3RvcgAAAAAAAAEAAAAAAAAABWFkbWluAAAAAAAAEwAAAAA=",
        "AAAAAAAAAAAAAAAHdXBncmFkZQAAAAABAAAAAAAAAAl3YXNtX2hhc2gAAAAAAAPuAAAAIAAAAAA=",
        "AAAABAAAAAAAAAAAAAAAD0NvbGxlY3Rpb25FcnJvcgAAAAABAAAAJEluZGljYXRlcyBhIG5vbi1leGlzdGVudCBgdG9rZW5faWRgLgAAABVOb25FeGlzdGVudENvbGxlY3Rpb24AAAAAAAEs",
        "AAAABQAAAAAAAAAAAAAAB1VwZ3JhZGUAAAAAAQAAAAd1cGdyYWRlAAAAAAIAAAAAAAAABWFkbWluAAAAAAAAEwAAAAAAAAAAAAAACXdhc21faGFzaAAAAAAAAA4AAAAAAAAAAg==",
      ]),
      options,
    );
  }
  public readonly fromJSON = {
    upgrade: this.txFromJSON<null>,
  };
}
