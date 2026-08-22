.PHONY: help install contract_build contract_test contract_lint contract_bindings contract_deploy_collection contract_upload_nft contract_create_collection contract_upload_account contract_deploy_factory contract_upload_pocket contract_configure_factory contract_set_factory contract_deploy_all contract_upgrade
.DEFAULT_GOAL := help
SHELL:=/bin/bash

ifndef network
   override network = testnet
endif

ifndef admin
	ifeq ($(network),testnet)
		   override admin = chimp-agent
	else
		   override admin = chimpdao_nft
	endif
endif

ifndef nfc_nft_wasm
override nfc_nft_wasm = target/wasm32v1-none/release/nfc_nft.wasm
endif

override nfc_nft_symbol_contract_id = $(shell cat .config/stellar/nfc_nft_$(symbol)_$(network)_id)
override nfc_nft_wasm_hash = $(shell cat $(nfc_nft_wasm) | openssl sha256 | cut -d " " -f2)
# override nfc_nft_wasm_hash = $(shell stellar contract fetch --id $(nfc_nft_contract_id) --network $(network) | openssl sha256 | cut -d " " -f2)

ifndef collection_wasm
override collection_wasm = target/wasm32v1-none/release/collection.wasm
endif

override collection_contract_id = $(shell cat .config/stellar/collection_$(network)_id)
override collection_wasm_hash = $(shell cat $(collection_wasm) | openssl sha256 | cut -d " " -f2)

ifndef prize_wasm
override prize_wasm = target/wasm32v1-none/release/prize.wasm
endif

override prize_contract_id = $(shell cat .config/stellar/prize_$(network)_id)
override native_contract_id = $(shell stellar contract id asset --asset native --network $(network))

ifndef pocket_wasm
override pocket_wasm = target/wasm32v1-none/release/chimpdao_pocket.wasm
endif
ifndef factory_wasm
override factory_wasm = target/wasm32v1-none/release/chimpdao_pocket_factory.wasm
endif
ifndef router_wasm
override router_wasm = target/wasm32v1-none/release/chimpdao_router.wasm
endif

override factory_contract_id = $(shell cat .config/stellar/pocket_factory_$(network)_id 2>/dev/null)
override pocket_wasm_hash = $(shell openssl sha256 $(pocket_wasm) 2>/dev/null | cut -d " " -f2)

# Defaults, not overrides: `symbol=` on the command line must actually select a
# campaign, or `contract_clawback symbol=chi2` silently claws a token out of chi1.
ifndef symbol
symbol = chi1
endif
ifndef name
name = "Palta Chimpy"
endif
ifndef max_tokens
max_tokens = 100
endif


# Save a contract id only if it looks like one; `stellar ... > file` otherwise writes
# error text that later targets read back as an id.
define save_id
	@out=$$(mktemp); \
	if $(1) > $$out 2>/dev/null; then \
		id=$$(tr -d '"[:space:]' < $$out); \
		case "$$id" in \
			C[A-Z2-7]*) mkdir -p $$(dirname $(2)); printf '%s' "$$id" > $(2); \
				echo "$(2) = $$id" ;; \
			*) echo "refusing to save non-contract-id output: $$id" >&2; rm -f $$out; exit 1 ;; \
		esac; \
	else \
		echo "deploy failed; $(2) left unchanged" >&2; cat $$out >&2; rm -f $$out; exit 1; \
	fi; \
	rm -f $$out
endef

# Add help text after each target name starting with '\#\#'
help:   ## show this help
	@echo -e "Help for this makefile\n"
	@echo "Possible commands are:"
	@grep -h "##" $(MAKEFILE_LIST) | grep -v grep | sed -e 's/\(.*\):.*##\(.*\)/    \1: \2/'

install:  ## install Rust and Soroban-CLI
	# uv for the pre-push hook
	curl -LsSf https://astral.sh/uv/install.sh | sh
	# install Rust
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh && \
	# install Soroban and config
	rustup target add wasm32v1-none && \
	cargo install --locked stellar-cli

funds:
	stellar keys fund $(admin) --network $(network)

# --------- CONTRACT BUILD/TEST/DEPLOY --------- #

contract_build:  ## Build all wasm
	stellar contract build --optimize
	@ls -l target/wasm32v1-none/release/*.wasm

# Only two tests need prebuilt wasm — collection's `create_collection` and the factory's
# `create_account` both deploy from a real wasm hash, which a mock cannot stand in for.
contract_test: contract_build  ## Build wasm then cargo test
	cargo test --workspace

contract_lint: ## Clippy + rustfmt, same gates as CI
	cargo clippy --workspace --all-targets -- -D warnings
	cargo fmt --all --check

# The terminal hand-writes its calls in src/chain/, so this is for inspecting an
# interface only. Output is gitignored.
contract_bindings: contract_build  ## Generate TypeScript bindings for inspection
	stellar contract bindings typescript \
		--network $(network) \
		--wasm $(nfc_nft_wasm) \
		--output-dir bindings/nfc_nft \
		--overwrite
	stellar contract bindings typescript \
		--network $(network) \
		--wasm $(collection_wasm) \
		--output-dir bindings/collection \
		--overwrite
	stellar contract bindings typescript \
		--network $(network) \
		--wasm $(pocket_wasm) \
		--output-dir bindings/pocket \
		--overwrite

contract_deploy_collection: contract_build  ## Deploy Soroban contract collection
	$(call save_id,stellar contract deploy \
  		--wasm $(collection_wasm) \
  		--source-account $(admin) \
  		--network $(network) \
  		--salt $(shell printf chi_collection_v5 | openssl sha256 | cut -d " " -f2) \
  		-- \
  		--admin $(admin),.config/stellar/collection_$(network)_id)

contract_upload_nft: contract_build  ## Upload Soroban contract NFT
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm $(nfc_nft_wasm) \
  		--source-account $(admin) \
  		--network $(network)

## Create NFT collection

contract_create_collection: contract_upload_nft  ## Deploy Soroban contract NFT via collection
	$(call save_id,stellar contract invoke \
		--resource-fee 10000000 \
		--source-account $(admin) \
		--network $(network) \
		--id $(collection_contract_id) \
		-- \
		create_collection \
		--wasm_hash $(nfc_nft_wasm_hash) \
		--name $(name) --symbol $(symbol) --max_tokens $(max_tokens) \
  		--uri https://ipfs.io/ipfs/bafybeihfqx4pstq4au6ueuzj4ns2ovmw237zfh2z2qvz6rxssdjzlnpcna,.config/stellar/nfc_nft_$(symbol)_$(network)_id)

## Prize (example)

contract_deploy_prize: contract_build  ## Deploy example prize contract
	stellar contract deploy \
  		--wasm $(prize_wasm) \
  		--source-account $(admin) \
  		--network $(network) \
  		--salt $(shell printf chimp_prize | openssl sha256 | cut -d " " -f2) \
  		-- \
  		--admin $(admin) \
  		--token $(native_contract_id) \
  		--nfc_contract $(nfc_nft_symbol_contract_id) \
  		> .config/stellar/prize_$(network)_id && \
  	cat .config/stellar/prize_$(network)_id

## Pocket / Earn (pocket + pocket-factory)

# Accounts deploy per holder from this installed wasm (terminal `createFreshAccount`).
contract_upload_account: contract_build  ## Install the Chimp account wasm, record its hash
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm target/wasm32v1-none/release/chimpdao_account.wasm \
		--source-account $(admin) \
		--network $(network)
	@mkdir -p .config/stellar
	@openssl sha256 target/wasm32v1-none/release/chimpdao_account.wasm | cut -d " " -f2 > .config/stellar/account_wasm_hash_$(network)
	@echo "account wasm hash = $$(cat .config/stellar/account_wasm_hash_$(network))"

contract_deploy_factory: contract_build  ## Deploy the Pocket factory (run contract_configure_factory next)
	$(call save_id,stellar contract deploy \
		--wasm $(factory_wasm) \
		--source-account $(admin) \
		--network $(network) \
		--salt $(shell printf chimp_pocket_factory_v4 | openssl sha256 | cut -d " " -f2) \
		-- \
		--admin $(admin),.config/stellar/pocket_factory_$(network)_id)

# The factory will not deploy until it has both a collection pointer and a pinned wasm.
contract_upload_pocket: contract_build  ## Upload the Pocket wasm and record its hash
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm $(pocket_wasm) \
		--source-account $(admin) \
		--network $(network)
	@mkdir -p .config/stellar
	@printf '%s' "$(pocket_wasm_hash)" > .config/stellar/pocket_wasm_hash_$(network)
	@echo "pocket wasm hash = $(pocket_wasm_hash)"

contract_configure_factory: contract_upload_pocket  ## Pin the Pocket wasm the factory deploys
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(factory_contract_id) \
		-- \
		set_pocket_wasm_hash \
		--wasm_hash $(pocket_wasm_hash)
	@echo "factory $(factory_contract_id) is ready to deploy accounts"

# The other half of the wiring: without it nfc-nft cannot resolve a card's purse, and
# `transfer` silently skips the purse handover instead of moving it with the card.
contract_set_factory:  ## Point nfc-nft at the Pocket factory (required for card handover)
	@test -n "$(factory_contract_id)" || { echo "no pocket_factory_$(network)_id — run contract_deploy_factory first"; exit 1; }
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(nfc_nft_symbol_contract_id) \
		-- \
		set_factory \
		--factory $(factory_contract_id)

# Whole bring-up in dependency order; a failed step leaves the previous ids intact.
# Atomic multi-call. Stateless, adminless pass-through: nothing to configure after
# deploying, and no upgrade path by design.
contract_deploy_router: contract_build  ## Deploy the atomic multi-call router
	$(call save_id,stellar contract deploy \
		--wasm $(router_wasm) \
		--source-account $(admin) \
		--network $(network) \
		--salt $(shell printf chimp_router_v2 | openssl sha256 | cut -d " " -f2),.config/stellar/router_$(network)_id)

contract_deploy_all: contract_deploy_collection contract_create_collection contract_upload_account contract_deploy_factory contract_configure_factory contract_set_factory  ## Full bring-up (fresh network only — never mainnet)
	@echo ""
	@echo "collection    $$(cat .config/stellar/collection_$(network)_id)"
	@echo "nfc-nft       $$(cat .config/stellar/nfc_nft_$(symbol)_$(network)_id)"
	@echo "pocket-factory $$(cat .config/stellar/pocket_factory_$(network)_id)"
	@echo "pocket wasm   $$(cat .config/stellar/pocket_wasm_hash_$(network))"

## Usage

contract_uri:  ## Read token 0's metadata URI from the live nfc-nft
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(nfc_nft_symbol_contract_id) \
		-- \
		token_uri \
		--token_id 0

# The one nfc-nft admin op with no home in the terminal: no chip needs to be present.
contract_clawback:  ## Claw a token back to the admin (symbol=… token_id=…)
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(nfc_nft_symbol_contract_id) \
		-- \
		clawback \
		--token_id $(token_id)

# Redeeming has no CLI path: it needs a chip attestation over
# ("redeem", [redeemer], nonce) under the prize domain — use the terminal's
# src/chain/chip-auth.ts.
contract_prize_deposit:  ## Lock 100 XLM against token 0 in the example prize contract
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(prize_contract_id) \
		-- \
		deposit \
		--from $(admin) \
		--amount 1000000000 \
		--token_id 0

## Upgrade

# `$(shell cat … 2>/dev/null)` yields an empty string for a network that was never
# brought up, so an unset id would upgrade nothing and report success. Fail before
# touching the network instead.
contract_upgrade: contract_build
	@test -n "$(nfc_nft_symbol_contract_id)" || { echo "no nfc_nft_$(symbol)_$(network)_id"; exit 1; }  ## In-place upgrade of live nfc-nft + collection to the freshly built wasm (token storage untouched)
	stellar contract upload \
		--wasm $(nfc_nft_wasm) \
		--source-account $(admin) \
		--network $(network)
	stellar contract upload \
		--wasm $(collection_wasm) \
		--source-account $(admin) \
		--network $(network)
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(nfc_nft_symbol_contract_id) \
		-- \
		upgrade \
		--wasm_hash $(nfc_nft_wasm_hash)
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(collection_contract_id) \
		-- \
		upgrade \
		--wasm_hash $(collection_wasm_hash)
	@echo "upgraded. If this network has a Pocket factory, run: make contract_set_factory network=$(network)"
