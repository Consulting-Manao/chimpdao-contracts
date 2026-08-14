# Prize (example)

Reference Soroban app: lock a SEP-41 token under a chip public key, redeem with nfc-nft ChipAuth + NFT ownership.

Not a core Chi//mp protocol contract. Use it to see how an integrator builds its own `call_digest` under its own domain and reads `curve` / `public_key` / `owner_of` / `token_id` from nfc-nft. The trusted nfc-nft address is bound at construction, not taken per call — copy that.

Build/test with the workspace (`make contract_test`). Deploy helper: `make contract_deploy_prize`.
