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

override symbol = chi1
override name = "Palta Chimpy"
override max_tokens = 100


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

contract_create_collection:  ## Deploy Soroban contract NFT via collection
	stellar contract invoke \
		--resource-fee 10000000 \
		--source-account $(admin) \
		--network $(network) \
		--id $(collection_contract_id) \
		-- \
		create_collection \
		--wasm_hash $(nfc_nft_wasm_hash) \
		--name $(name) --symbol $(symbol) --max_tokens $(max_tokens) \
  		--uri https://ipfs.io/ipfs/bafybeihfqx4pstq4au6ueuzj4ns2ovmw237zfh2z2qvz6rxssdjzlnpcna \
  		> .config/stellar/nfc_nft_$(symbol)_$(network)_id && \
  	cat .config/stellar/nfc_nft_$(symbol)_$(network)_id

## Prize

contract_deploy_prize: contract_build  ## Deploy Soroban contract prize
	stellar contract deploy \
  		--wasm $(prize_wasm) \
  		--source-account $(admin) \
  		--network $(network) \
  		--salt $(shell printf chimp_prize | openssl sha256 | cut -d " " -f2) \
  		-- \
  		--admin $(admin) \
  		--token $(native_contract_id) \
  		> .config/stellar/prize_$(network)_id && \
  	cat .config/stellar/prize_$(network)_id

## Usage

contract_uri:
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(nfc_nft_symbol_contract_id) \
		-- \
		token_uri \
		--token_id 0

contract_prize_deposit:
	stellar contract invoke \
		--source-account $(admin) \
		--network $(network) \
		--id $(prize_contract_id) \
		-- \
		deposit \
		--from $(admin) \
		--amount 1000000000 \
		--nfc_contract $(nfc_nft_symbol_contract_id) \
		--token_id 0

# use dapp to make new signatures
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
