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

export type DataKey =
  | { tag: "Admin"; values: void }
  | { tag: "NextTokenId"; values: void }
  | { tag: "MaxTokens"; values: void };

export type NFTStorageKey =
  | { tag: "ChipNonceByPublicKey"; values: readonly [Buffer] }
  | { tag: "Owner"; values: readonly [u64] }
  | { tag: "PublicKey"; values: readonly [u64] }
  | { tag: "TokenIdByPublicKey"; values: readonly [Buffer] }
  | { tag: "Balance"; values: readonly [string] }
  | { tag: "Name"; values: void }
  | { tag: "Symbol"; values: void }
  | { tag: "URI"; values: void };

export const NonFungibleTokenError = {
  /**
   * Indicates a non-existent `token_id`.
   */
  200: { message: "NonExistentToken" },
  /**
   * Indicates an error related to the ownership over a particular token.
   * Used in transfers.
   */
  201: { message: "IncorrectOwner" },
  /**
   * Indicates overflow when adding two values
   */
  205: { message: "MathOverflow" },
  /**
   * Indicates all possible `token_id`s are already in use.
   */
  206: { message: "TokenIDsAreDepleted" },
  /**
   * Indicates an invalid amount to batch mint in `consecutive` extension.
   */
  207: { message: "InvalidAmount" },
  /**
   * Indicates the token was already minted.
   */
  210: { message: "TokenAlreadyMinted" },
  /**
   * Indicates the royalty amount is higher than 10_000 (100%) basis points.
   */
  212: { message: "InvalidRoyaltyAmount" },
  /**
   * Indicates an invalid signature
   */
  214: { message: "InvalidSignature" },
  /**
   * Indicates the token exists but has not been claimed yet
   */
  215: { message: "TokenNotClaimed" },
};

export interface Client {
  /**
   * Construct and simulate a upgrade transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  upgrade: (
    { wasm_hash }: { wasm_hash: Buffer },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<null>>;

  /**
   * Construct and simulate a mint transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  mint: (
    {
      message,
      signature,
      recovery_id,
      public_key,
      nonce,
    }: {
      message: Buffer;
      signature: Buffer;
      recovery_id: u32;
      public_key: Buffer;
      nonce: u32;
    },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<u64>>;

  /**
   * Construct and simulate a claim transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  claim: (
    {
      claimant,
      message,
      signature,
      recovery_id,
      public_key,
      nonce,
    }: {
      claimant: string;
      message: Buffer;
      signature: Buffer;
      recovery_id: u32;
      public_key: Buffer;
      nonce: u32;
    },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<u64>>;

  /**
   * Construct and simulate a transfer transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  transfer: (
    {
      from,
      to,
      token_id,
      message,
      signature,
      recovery_id,
      public_key,
      nonce,
    }: {
      from: string;
      to: string;
      token_id: u64;
      message: Buffer;
      signature: Buffer;
      recovery_id: u32;
      public_key: Buffer;
      nonce: u32;
    },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<null>>;

  /**
   * Construct and simulate a get_nonce transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  get_nonce: (
    { public_key }: { public_key: Buffer },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<u32>>;

  /**
   * Construct and simulate a balance transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  balance: (
    { owner }: { owner: string },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<u32>>;

  /**
   * Construct and simulate a owner_of transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  owner_of: (
    { token_id }: { token_id: u64 },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<string>>;

  /**
   * Construct and simulate a name transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  name: (options?: MethodOptions) => Promise<AssembledTransaction<string>>;

  /**
   * Construct and simulate a symbol transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  symbol: (options?: MethodOptions) => Promise<AssembledTransaction<string>>;

  /**
   * Construct and simulate a token_uri transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  token_uri: (
    { token_id }: { token_id: u64 },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<string>>;

  /**
   * Construct and simulate a token_id transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  token_id: (
    { public_key }: { public_key: Buffer },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<u64>>;

  /**
   * Construct and simulate a public_key transaction. Returns an `AssembledTransaction` object which will have a `result` field containing the result of the simulation. If this transaction changes contract state, you will need to call `signAndSend()` on the returned object.
   */
  public_key: (
    { token_id }: { token_id: u64 },
    options?: MethodOptions,
  ) => Promise<AssembledTransaction<Buffer>>;
}
export class Client extends ContractClient {
  static async deploy<T = Client>(
    /** Constructor/Initialization Args for the contract's `__constructor` method */
    {
      admin,
      name,
      symbol,
      uri,
      max_tokens,
    }: {
      admin: string;
      name: string;
      symbol: string;
      uri: string;
      max_tokens: u64;
    },
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
    return ContractClient.deploy(
      { admin, name, symbol, uri, max_tokens },
      options,
    );
  }
  constructor(public readonly options: ContractClientOptions) {
    super(
      new ContractSpec([
        "AAAAAgAAAAAAAAAAAAAAB0RhdGFLZXkAAAAAAwAAAAAAAAAAAAAABUFkbWluAAAAAAAAAAAAAAAAAAALTmV4dFRva2VuSWQAAAAAAAAAAAAAAAAJTWF4VG9rZW5zAAAA",
        "AAAAAgAAAAAAAAAAAAAADU5GVFN0b3JhZ2VLZXkAAAAAAAAIAAAAAQAAAAAAAAAUQ2hpcE5vbmNlQnlQdWJsaWNLZXkAAAABAAAD7gAAAEEAAAABAAAAAAAAAAVPd25lcgAAAAAAAAEAAAAGAAAAAQAAAAAAAAAJUHVibGljS2V5AAAAAAAAAQAAAAYAAAABAAAAAAAAABJUb2tlbklkQnlQdWJsaWNLZXkAAAAAAAEAAAPuAAAAQQAAAAEAAAAAAAAAB0JhbGFuY2UAAAAAAQAAABMAAAAAAAAAAAAAAAROYW1lAAAAAAAAAAAAAAAGU3ltYm9sAAAAAAAAAAAAAAAAAANVUkkA",
        "AAAAAAAAAAAAAAANX19jb25zdHJ1Y3RvcgAAAAAAAAUAAAAAAAAABWFkbWluAAAAAAAAEwAAAAAAAAAEbmFtZQAAABAAAAAAAAAABnN5bWJvbAAAAAAAEAAAAAAAAAADdXJpAAAAABAAAAAAAAAACm1heF90b2tlbnMAAAAAAAYAAAAA",
        "AAAAAAAAAAAAAAAHdXBncmFkZQAAAAABAAAAAAAAAAl3YXNtX2hhc2gAAAAAAAPuAAAAIAAAAAA=",
        "AAAAAAAAAAAAAAAEbWludAAAAAUAAAAAAAAAB21lc3NhZ2UAAAAADgAAAAAAAAAJc2lnbmF0dXJlAAAAAAAD7gAAAEAAAAAAAAAAC3JlY292ZXJ5X2lkAAAAAAQAAAAAAAAACnB1YmxpY19rZXkAAAAAA+4AAABBAAAAAAAAAAVub25jZQAAAAAAAAQAAAABAAAABg==",
        "AAAAAAAAAAAAAAAFY2xhaW0AAAAAAAAGAAAAAAAAAAhjbGFpbWFudAAAABMAAAAAAAAAB21lc3NhZ2UAAAAADgAAAAAAAAAJc2lnbmF0dXJlAAAAAAAD7gAAAEAAAAAAAAAAC3JlY292ZXJ5X2lkAAAAAAQAAAAAAAAACnB1YmxpY19rZXkAAAAAA+4AAABBAAAAAAAAAAVub25jZQAAAAAAAAQAAAABAAAABg==",
        "AAAAAAAAAAAAAAAIdHJhbnNmZXIAAAAIAAAAAAAAAARmcm9tAAAAEwAAAAAAAAACdG8AAAAAABMAAAAAAAAACHRva2VuX2lkAAAABgAAAAAAAAAHbWVzc2FnZQAAAAAOAAAAAAAAAAlzaWduYXR1cmUAAAAAAAPuAAAAQAAAAAAAAAALcmVjb3ZlcnlfaWQAAAAABAAAAAAAAAAKcHVibGljX2tleQAAAAAD7gAAAEEAAAAAAAAABW5vbmNlAAAAAAAABAAAAAA=",
        "AAAAAAAAAAAAAAAJZ2V0X25vbmNlAAAAAAAAAQAAAAAAAAAKcHVibGljX2tleQAAAAAD7gAAAEEAAAABAAAABA==",
        "AAAAAAAAAAAAAAAHYmFsYW5jZQAAAAABAAAAAAAAAAVvd25lcgAAAAAAABMAAAABAAAABA==",
        "AAAAAAAAAAAAAAAIb3duZXJfb2YAAAABAAAAAAAAAAh0b2tlbl9pZAAAAAYAAAABAAAAEw==",
        "AAAAAAAAAAAAAAAEbmFtZQAAAAAAAAABAAAAEA==",
        "AAAAAAAAAAAAAAAGc3ltYm9sAAAAAAAAAAAAAQAAABA=",
        "AAAAAAAAAAAAAAAJdG9rZW5fdXJpAAAAAAAAAQAAAAAAAAAIdG9rZW5faWQAAAAGAAAAAQAAABA=",
        "AAAAAAAAAAAAAAAIdG9rZW5faWQAAAABAAAAAAAAAApwdWJsaWNfa2V5AAAAAAPuAAAAQQAAAAEAAAAG",
        "AAAAAAAAAAAAAAAKcHVibGljX2tleQAAAAAAAQAAAAAAAAAIdG9rZW5faWQAAAAGAAAAAQAAA+4AAABB",
        "AAAABAAAAAAAAAAAAAAAFU5vbkZ1bmdpYmxlVG9rZW5FcnJvcgAAAAAAAAkAAAAkSW5kaWNhdGVzIGEgbm9uLWV4aXN0ZW50IGB0b2tlbl9pZGAuAAAAEE5vbkV4aXN0ZW50VG9rZW4AAADIAAAAV0luZGljYXRlcyBhbiBlcnJvciByZWxhdGVkIHRvIHRoZSBvd25lcnNoaXAgb3ZlciBhIHBhcnRpY3VsYXIgdG9rZW4uClVzZWQgaW4gdHJhbnNmZXJzLgAAAAAOSW5jb3JyZWN0T3duZXIAAAAAAMkAAAApSW5kaWNhdGVzIG92ZXJmbG93IHdoZW4gYWRkaW5nIHR3byB2YWx1ZXMAAAAAAAAMTWF0aE92ZXJmbG93AAAAzQAAADZJbmRpY2F0ZXMgYWxsIHBvc3NpYmxlIGB0b2tlbl9pZGBzIGFyZSBhbHJlYWR5IGluIHVzZS4AAAAAABNUb2tlbklEc0FyZURlcGxldGVkAAAAAM4AAABFSW5kaWNhdGVzIGFuIGludmFsaWQgYW1vdW50IHRvIGJhdGNoIG1pbnQgaW4gYGNvbnNlY3V0aXZlYCBleHRlbnNpb24uAAAAAAAADUludmFsaWRBbW91bnQAAAAAAADPAAAAJ0luZGljYXRlcyB0aGUgdG9rZW4gd2FzIGFscmVhZHkgbWludGVkLgAAAAASVG9rZW5BbHJlYWR5TWludGVkAAAAAADSAAAAR0luZGljYXRlcyB0aGUgcm95YWx0eSBhbW91bnQgaXMgaGlnaGVyIHRoYW4gMTBfMDAwICgxMDAlKSBiYXNpcyBwb2ludHMuAAAAABRJbnZhbGlkUm95YWx0eUFtb3VudAAAANQAAAAeSW5kaWNhdGVzIGFuIGludmFsaWQgc2lnbmF0dXJlAAAAAAAQSW52YWxpZFNpZ25hdHVyZQAAANYAAAA3SW5kaWNhdGVzIHRoZSB0b2tlbiBleGlzdHMgYnV0IGhhcyBub3QgYmVlbiBjbGFpbWVkIHlldAAAAAAPVG9rZW5Ob3RDbGFpbWVkAAAAANc=",
        "AAAABQAAAAAAAAAAAAAAB1VwZ3JhZGUAAAAAAQAAAAd1cGdyYWRlAAAAAAIAAAAAAAAABWFkbWluAAAAAAAAEwAAAAAAAAAAAAAACXdhc21faGFzaAAAAAAAAA4AAAAAAAAAAg==",
        "AAAABQAAAAAAAAAAAAAACFRyYW5zZmVyAAAAAQAAAAh0cmFuc2ZlcgAAAAMAAAAAAAAABGZyb20AAAATAAAAAQAAAAAAAAACdG8AAAAAABMAAAABAAAAAAAAAAh0b2tlbl9pZAAAAAYAAAAAAAAAAg==",
        "AAAABQAAAAAAAAAAAAAABE1pbnQAAAABAAAABG1pbnQAAAABAAAAAAAAAAh0b2tlbl9pZAAAAAYAAAABAAAAAg==",
        "AAAABQAAAAAAAAAAAAAABUNsYWltAAAAAAAAAQAAAAVjbGFpbQAAAAAAAAIAAAAAAAAACGNsYWltYW50AAAAEwAAAAEAAAAAAAAACHRva2VuX2lkAAAABgAAAAAAAAAC",
      ]),
      options,
    );
  }
  public readonly fromJSON = {
    upgrade: this.txFromJSON<null>,
    mint: this.txFromJSON<u64>,
    claim: this.txFromJSON<u64>,
    transfer: this.txFromJSON<null>,
    get_nonce: this.txFromJSON<u32>,
    balance: this.txFromJSON<u32>,
    owner_of: this.txFromJSON<string>,
    name: this.txFromJSON<string>,
    symbol: this.txFromJSON<string>,
    token_uri: this.txFromJSON<string>,
    token_id: this.txFromJSON<u64>,
    public_key: this.txFromJSON<Buffer>,
  };
}
