# Contributing

Contributions are welcome. This guide covers how to contribute code, where to
report issues, and how to get in touch.

## Contributing code

1. Fork the repository at
   [Consulting-Manao/chimpdao-contracts](https://github.com/Consulting-Manao/chimpdao-contracts)
   and create a feature branch off `main`.
2. Make sure your toolchain matches [`rust-toolchain.toml`](rust-toolchain.toml)
   and that the `wasm32v1-none` target is installed (`make install` covers
   this).
3. Run the contract test suite before opening a pull request:

   ```bash
   make contract_build
   make contract_test    # equivalent to cargo test across the workspace
   cargo fmt --all -- --check
   ```

4. For changes to the TypeScript dApp under [`dapp/`](dapp), run
   `bun run lint` and `bun run format` from that directory.
5. Open a pull request against `main`. Continuous integration
   ([`.github/workflows/contract.yml`](.github/workflows/contract.yml))
   re-runs the build and the test suite; please make sure it stays green.
6. Smart contracts are security-sensitive code. Pull requests that touch
   [`contracts/`](contracts/) should describe the threat model implication of
   the change and reference the relevant tests. Maintainers may ask for an
   independent review before merging.

## Reporting issues

- General bug reports and feature requests:
  [GitHub Issues](https://github.com/Consulting-Manao/chimpdao-contracts/issues).
- Suspected security vulnerabilities: see [`SECURITY.md`](SECURITY.md) and
  use GitHub's private vulnerability reporting flow rather than opening a
  public issue.
- Documentation problems are tracked through the same issue tracker; please
  prefix the title with `docs:`.

## Getting in touch

- Public discussion happens in
  [GitHub Issues](https://github.com/Consulting-Manao/chimpdao-contracts/issues)
  and pull requests.
- Project funding history and roadmap: the
  [SCF #38 submission](https://communityfund.stellar.org/submissions/rece7XluClIM1t7EL).

All interactions are governed by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Updating deployments

When deploying a new version of the contracts:

1. Update the relevant ID file under
   [`.config/stellar/`](.config/stellar) (for example,
   `collection_testnet_id` or `nfc_nft_chi1_mainnet_id`).
2. Update `.env` and `.env.example` in [`dapp/`](dapp) with the new contract
   ID.
3. Update the Xcode build settings in the companion iOS application
   (`STELLAR_CONTRACT_ID_TESTNET` or `STELLAR_CONTRACT_ID_MAINNET`).
4. Set the network in the dApp configuration (`STELLAR_NETWORK`: `testnet`
   or `mainnet`).
