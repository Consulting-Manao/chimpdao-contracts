.PHONY: help install contract_build contract_test contract_bindings contract_deploy_collection contract_upload_nft contract_create_collection contract_deploy_nft contract_help
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

override nfc_nft_contract_id = $(shell cat .config/stellar/nfc_nft_$(network)_id)
override nfc_nft_wasm_hash = $(shell stellar contract fetch --id $(nfc_nft_contract_id) --network $(network) | openssl sha256 | cut -d " " -f2)

ifndef collection_wasm
override collection_wasm = target/wasm32v1-none/release/collection.wasm
endif

override collection_contract_id = $(shell cat .config/stellar/collection_$(network)_id)
override collection_wasm_hash = $(shell stellar contract fetch --id $(collection_contract_id) --network $(network) | openssl sha256 | cut -d " " -f2)

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

contract_build:
	stellar contract build --optimize
	@ls -l target/wasm32v1-none/release/*.wasm

contract_test:
	cargo test

contract_bindings: contract_build  ## Create bindings
	stellar contract bindings typescript \
		--network $(network) \
		--wasm $(nfc_nft_wasm) \
		--output-dir dapp/packages/nfc_nft \
		--overwrite && \
	cd dapp/packages/nfc_nft && \
	bun install --latest && \
	bun run build && \
	cd ../../.. && \
	stellar contract bindings typescript \
		--network $(network) \
		--wasm $(collection_wasm) \
		--output-dir dapp/packages/collection \
		--overwrite && \
	cd dapp/packages/collection && \
	bun install --latest && \
	bun run build && \
	cd ../.. && \
	bun format

contract_deploy_collection: contract_build  ## Deploy Soroban contract collection
	stellar contract deploy \
  		--wasm $(collection_wasm) \
  		--source-account $(admin) \
  		--network $(network) \
  		--salt $(shell printf chi_collection | openssl sha256 | cut -d " " -f2) \
  		-- \
  		--admin $(admin) \
  		> .config/stellar/collection_$(network)_id && \
  	cat .config/stellar/collection_$(network)_id

contract_upload_nft: contract_build  ## Upload Soroban contract NFT
	stellar contract upload \
		--wasm $(nfc_nft_wasm) \
  		--source-account $(admin) \
  		--network $(network)

## Create NFT collection

contract_deploy_nft: contract_build  ## Deploy Soroban contract NFT directly
	stellar contract deploy \
  		--wasm $(nfc_nft_wasm) \
  		--source-account $(admin) \
  		--network $(network) \
  		--salt $(shell printf chi1 | openssl sha256 | cut -d " " -f2) \
  		-- \
  		--admin $(admin) \
  		--collection_contract $(collection_contract_id) \
  		--name "Palta Chimpy" --symbol chi1 --max_tokens 100 \
  		--uri https://ipfs.io/ipfs/bafybeihfqx4pstq4au6ueuzj4ns2ovmw237zfh2z2qvz6rxssdjzlnpcna \
  		> .config/stellar/nfc_nft_$(network)_id && \
  	cat .config/stellar/nfc_nft_$(network)_id

contract_create_collection:  ## Deploy Soroban contract NFT via collection
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(collection_contract_id) \
		-- \
		create_collection \
		--wasm_hash $(nfc_nft_wasm_hash) \
		--name "Palta Chimpy" --symbol "chi1" --max_tokens 100 \
  		--uri https://ipfs.io/ipfs/bafybeihfqx4pstq4au6ueuzj4ns2ovmw237zfh2z2qvz6rxssdjzlnpcna

## Usage

contract_uri:
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(nfc_nft_contract_id) \
		-- \
		token_uri \
		--token_id 0
