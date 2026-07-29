/**
 * No hardware needed: checks that a SELECT which fails transiently (as a
 * freshly tapped card does) is retried, and that a card that never answers
 * still fails and clears the card state.
 *
 * Run: node scripts/test-select-retry.js
 */
import assert from "node:assert/strict";
import { BLOCKCHAIN_AID } from "../lib/constants.js";
import { BlockchainOperations } from "../lib/blockchain-ops.js";

/** Fails the first `failures` transmits, then answers SELECT with 9000. */
function stub(failures) {
  const state = { present: true, cleared: 0, transmits: 0, connects: 0 };
  const reader = {
    connection: { protocol: 1 },
    connect: async () => {
      state.connects++;
      reader.connection = { protocol: 1 };
    },
    disconnect: async () => {
      reader.connection = null;
    },
    transmit: async () => {
      state.transmits++;
      if (state.transmits <= failures) {
        throw new Error("An error occurred while transmitting.");
      }
      return Buffer.concat([BLOCKCHAIN_AID, Buffer.from([0x90, 0x00])]);
    },
  };
  const manager = {
    getReader: () => reader,
    getCard: () => ({ type: "TAG_ISO_14443_4" }),
    isChipPresent: () => state.present,
    verifyConnection: () => state.present,
    clearCardState: () => {
      state.cleared++;
      state.present = false;
    },
  };
  return { ops: new BlockchainOperations(manager), state };
}

const flaky = stub(2);
assert.equal(await flaky.ops.selectApplication(), true);
assert.equal(flaky.state.transmits, 3, "should retry until the card answers");
assert.equal(flaky.state.connects, 2, "each retry reconnects the card handle");
assert.equal(flaky.state.cleared, 0, "a recovered card keeps its state");

const dead = stub(Infinity);
await assert.rejects(() => dead.ops.selectApplication(), /transmit SELECT/);
assert.equal(dead.state.cleared, 1, "giving up must force a re-tap");
assert.ok(dead.state.transmits > 1 && dead.state.transmits <= 4);

// ponytail: same pattern as NFCServer.runApdu — second op waits for the first
let order = "";
let apdu = Promise.resolve();
const run = (fn) => (apdu = apdu.then(fn, fn));
await Promise.all([
  run(async () => {
    await new Promise((r) => setTimeout(r, 20));
    order += "a";
  }),
  run(async () => {
    order += "b";
  }),
]);
assert.equal(order, "ab", "APDU ops must not interleave");

console.log("select retry ok");
