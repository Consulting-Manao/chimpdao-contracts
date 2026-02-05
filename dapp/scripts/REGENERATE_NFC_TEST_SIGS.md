# Regenerating NFC test signatures (one-shot)

Single source of truth for updating the 5 test signatures and chip public keys used by `contracts/nfc-nft/src/test.rs`. Use this when you need to regenerate some or all signatures (e.g. after changing the message hash formula or rotating chips).

## Prerequisites

- Repo root has `cargo` and `contracts/nfc-nft` builds.
- From repo root, `node dapp/scripts/recover-test-sigs.cjs` runs (Node with `@noble/secp256k1`; dapp deps installed).
- For signing: `uv run --with blocksec2go blocksec2go` (BlockSec2Go) and two NFC chips (Chip 1 for hashes 1–3, Chip 2 for hashes 4–5).

## One-shot steps

1. **Get the 5 message hashes** (same order as tests use):

   ```bash
   cargo test -p nfc-nft test_print_message_hash_for_signing -- --nocapture
   ```

   Copy the five lines like `Message hash (hex): <64 hex chars>` (hash 1 = Chip 1 mint, 2 = Chip 1 claim, 3 = Chip 1 transfer, 4 = Chip 2 mint, 5 = Chip 2 claim).

2. **Sign each hash** with the correct chip:
   - Hash 1, 2, 3 → Chip 1 (e.g. `uv run --with blocksec2go blocksec2go generate_signature 1 <hash_hex>`).
   - Hash 4, 5 → Chip 2 (e.g. `generate_signature 2 <hash_hex>`).
     You get 5 DER signatures (hex strings).

3. **Paste the 5 DER signatures** into `dapp/scripts/recover-test-sigs.cjs`: replace the array `DER_SIGS` so it contains exactly 5 hex strings (order: sig for hash 1, 2, 3, 4, 5).

4. **Run the recovery script from repo root**:

   ```bash
   node dapp/scripts/recover-test-sigs.cjs
   ```

   The script fetches the current hashes from the nfc-nft test (so hashes stay in sync). It prints Rust code.

5. **Paste the script output into `contracts/nfc-nft/src/test.rs`**:
   - Replace the **entire** `const CHIP1_PUBLIC_KEY: [u8; 65] = [ ... ];` with the script’s `CHIP1_PUBLIC_KEY` block.
   - Replace the **entire** `const CHIP2_PUBLIC_KEY: [u8; 65] = [ ... ];` with the script’s `CHIP2_PUBLIC_KEY` block.
   - For each of the **5** `TestSignature { ... }` entries (in order: Chip 1 nonce 1, Chip 1 nonce 2, Chip 1 nonce 3, Chip 2 nonce 3, Chip 2 nonce 4), replace **only** the `sig_r: [ ... ],` and `sig_s: [ ... ],` fields (the two 2-line arrays) with the corresponding `// --- Signature N ---` block from the script (each block is 8 lines: `sig_r: [` + 2 lines + `],` + `sig_s: [` + 2 lines + `],`). Do not change `nonce`, `message`, or `public_key` in those structs.

6. **Verify**:
   ```bash
   cargo test -p nfc-nft
   ```
   All 7 tests must pass.

## Files involved

| File                                 | Role                                                                                                  |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `dapp/scripts/recover-test-sigs.cjs` | Only recovery script. Input: `DER_SIGS`. Fetches hashes from test. Output: Rust for `test.rs`.        |
| `contracts/nfc-nft/src/test.rs`      | Holds `CHIP1_PUBLIC_KEY`, `CHIP2_PUBLIC_KEY`, and `TEST_SIGNATURES` (5 entries with `sig_r`/`sig_s`). |

## If the script fails

- **"Could not find Chip 1 public key consistent with sigs 0, 1, 2"** (or Chip 2): The 5 DER signatures don’t match the 5 hashes or chips (e.g. wrong hash order, or sig from wrong chip). Re-check that hash 1–3 are signed by Chip 1 and hash 4–5 by Chip 2, and that hashes match the test output.
- **"Warning: could not get hashes from test"**: Script fell back to built-in hashes. Run from **repo root** so `cargo test -p nfc-nft ...` can run; otherwise paste the 5 hashes from step 1 into the script’s `FALLBACK_HASHES` (or fix cwd).
