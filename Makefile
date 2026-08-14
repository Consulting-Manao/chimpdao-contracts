.PHONY: help install contract_build contract_test contract_bindings contract_deploy_collection contract_upload_nft contract_create_collection contract_deploy_nft contract_deploy_chip_verifier contract_deploy_factory contract_help
.DEFAULT_GOAL := help
SHELL:=/bin/bash

ifndef network
   override network = testnet
endif

ifndef admin
	ifeq ($(network),testnet)
		   override admin = me
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
override collection_wasm_hash = $(shell stellar contract fetch --id $(collection_contract_id) --network $(network) | openssl sha256 | cut -d " " -f2)

ifndef prize_wasm
override prize_wasm = target/wasm32v1-none/release/prize.wasm
endif

override prize_contract_id = $(shell cat .config/stellar/prize_$(network)_id)
override native_contract_id = $(shell stellar contract id asset --asset native --network $(network))

ifndef smart_account_wasm
override smart_account_wasm = target/wasm32v1-none/release/chimpdao_smart_account.wasm
endif
ifndef factory_wasm
override factory_wasm = target/wasm32v1-none/release/chimpdao_smart_account_factory.wasm
endif
ifndef chip_verifier_wasm
override chip_verifier_wasm = target/wasm32v1-none/release/chimpdao_chip_verifier.wasm
endif

override factory_contract_id = $(shell cat .config/stellar/smart_account_factory_$(network)_id 2>/dev/null)
override chip_verifier_contract_id = $(shell cat .config/stellar/chip_verifier_$(network)_id 2>/dev/null)
override smart_account_wasm_hash = $(shell openssl sha256 $(smart_account_wasm) 2>/dev/null | cut -d " " -f2)

override symbol = chi1
override name = "Palta Chimpy"
override max_tokens = 100


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

# `contractimport!` reads target/wasm32v1-none/release/, so producers build first.
contract_build:  ## Build all wasm, in dependency order
	stellar contract build --optimize --package collection
	stellar contract build --optimize --package nfc-nft
	stellar contract build --optimize --package chimpdao-smart-account
	stellar contract build --optimize
	@ls -l target/wasm32v1-none/release/*.wasm

contract_test: contract_build  ## Build wasm then cargo test (contracts import each other's wasm)
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
		--wasm $(smart_account_wasm) \
		--output-dir bindings/smart_account \
		--overwrite

contract_deploy_collection: contract_build  ## Deploy Soroban contract collection
	$(call save_id,stellar contract deploy \
  		--wasm $(collection_wasm) \
  		--source-account $(admin) \
  		--network $(network) \
  		--salt $(shell printf chi_collection_v2 | openssl sha256 | cut -d " " -f2) \
  		-- \
  		--admin $(admin),.config/stellar/collection_$(network)_id)

contract_upload_nft: contract_build  ## Upload Soroban contract NFT
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm $(nfc_nft_wasm) \
  		--source-account $(admin) \
  		--network $(network)

## Create NFT collection

contract_deploy_nft:  ## Deploy Soroban contract NFT directly
	stellar contract deploy \
		--resource-fee 150000000 \
  		--wasm $(nfc_nft_wasm) \
  		--source-account $(admin) \
  		--network $(network) \
  		--salt $(shell printf $(symbol) | openssl sha256 | cut -d " " -f2) \
  		-- \
  		--admin $(admin) \
  		--collection_contract $(collection_contract_id) \
  		--name $(name) --symbol $(symbol) --max_tokens $(max_tokens) \
  		--uri https://ipfs.io/ipfs/bafybeihfqx4pstq4au6ueuzj4ns2ovmw237zfh2z2qvz6rxssdjzlnpcna \
  		> .config/stellar/nfc_nft_$(network)_id && \
  	cat .config/stellar/nfc_nft_$(network)_id

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

## Pocket / Earn (smart-account + factory + chip-verifier)

contract_deploy_chip_verifier: contract_build  ## Deploy shared chip Verifier for Earn (Nido External)
	$(call save_id,stellar contract deploy \
		--wasm $(chip_verifier_wasm) \
		--source-account $(admin) \
		--network $(network) \
		--salt $(shell printf chimp_chip_verifier_v2 | openssl sha256 | cut -d " " -f2),.config/stellar/chip_verifier_$(network)_id)

contract_deploy_factory: contract_build  ## Deploy the Pocket factory (run contract_configure_factory next)
	$(call save_id,stellar contract deploy \
		--wasm $(factory_wasm) \
		--source-account $(admin) \
		--network $(network) \
		--salt $(shell printf chimp_pocket_factory_v2 | openssl sha256 | cut -d " " -f2) \
		-- \
		--admin $(admin),.config/stellar/smart_account_factory_$(network)_id)

# The factory will not deploy until it has both a collection pointer and a pinned wasm.
contract_upload_pocket: contract_build  ## Upload the Pocket wasm and record its hash
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm $(smart_account_wasm) \
		--source-account $(admin) \
		--network $(network)
	@mkdir -p .config/stellar
	@printf '%s' "$(smart_account_wasm_hash)" > .config/stellar/smart_account_wasm_hash_$(network)
	@echo "pocket wasm hash = $(smart_account_wasm_hash)"

contract_configure_factory: contract_upload_pocket  ## Point the factory at the collection + Pocket wasm
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(factory_contract_id) \
		-- \
		set_collection \
		--collection_contract $(collection_contract_id)
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(factory_contract_id) \
		-- \
		set_pocket_wasm_hash \
		--wasm_hash $(smart_account_wasm_hash)
	@echo "factory $(factory_contract_id) is ready to deploy accounts"

# Whole bring-up in dependency order; a failed step leaves the previous ids intact.
contract_deploy_all: contract_deploy_collection contract_create_collection contract_deploy_chip_verifier contract_deploy_factory contract_configure_factory  ## Full bring-up
	@echo ""
	@echo "collection    $$(cat .config/stellar/collection_$(network)_id)"
	@echo "nfc-nft       $$(cat .config/stellar/nfc_nft_$(symbol)_$(network)_id)"
	@echo "chip-verifier $$(cat .config/stellar/chip_verifier_$(network)_id)"
	@echo "factory       $$(cat .config/stellar/smart_account_factory_$(network)_id)"
	@echo "pocket wasm   $$(cat .config/stellar/smart_account_wasm_hash_$(network))"

## Usage

contract_uri:
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

contract_prize_deposit:
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(prize_contract_id) \
		-- \
		deposit \
		--from $(admin) \
		--amount 1000000000 \
		--token_id 0

# Needs a chip attestation over ("redeem", [redeemer], nonce) under the prize domain.
# No CLI path for that — use the terminal's src/chain/chip-auth.ts.
contract_prize_redeem:
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(prize_contract_id) \
		-- \
		redeem \
		--redeemer $(admin) \
		--nfc_contract $(nfc_nft_symbol_contract_id) \
		--message 68656c6c6f \
		--signature 38e50dbb0e7846aeafeba90ef32727cd5e5141e90b07c91ede26564039a8e873697f4f726f3827ecacbb46664e4b5f685d976284ea54d13d557e55733671f617 \
		--recovery_id 1 \
		--public_key 041e83a31ced7662d909a9eb3f746ce7d385c8f699efe851e318bd2fcfb754a8996495cae0e303e19f2bf9c6542231c5ab30d7aae7a0faf3f59ef94ad5bd275efb \
		--nonce 13

## Upgrade

contract_upload_releases:  ## Upload Soroban contracts from release job
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm contracts/collection_v1.0.0.wasm \
  		--source-account $(admin) \
  		--network $(network) && \
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm contracts/nfc-nft_v1.0.0.wasm \
  		--source-account $(admin) \
		--network $(network) && \
	stellar contract upload \
		--resource-fee 150000000 \
		--wasm contracts/prize_v1.0.0.wasm \
		--source-account $(admin) \
		--network $(network)

contract_upgrade:
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(nfc_nft_symbol_contract_id) \
		-- \
		upgrade \
		--wasm_hash 63351143b7b1e761b8e6b9e5d0e087364787f7cfedaf84dc5bd50d8a1d9268e6 && \
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(collection_contract_id) \
		-- \
		upgrade \
		--wasm_hash 7725fab80f17f39a1afcf7372c8be2fb842fe63be0af34988edf176b3d3be081 && \
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(prize_contract_id) \
		-- \
		upgrade \
		--wasm_hash 08dcb1dbb7a2dab1ed76e621dcac0cc7ca9d2457b6133fe0c9570772268df4d5
