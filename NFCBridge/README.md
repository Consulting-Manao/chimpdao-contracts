# NFC Bridge - Standalone iOS App

Standalone iOS app for NFC-based NFT minting using Infineon SECORA Blockchain NFC chips.

## Overview

This app allows users to mint NFTs directly from their iPhone by:
1. Reading an Infineon NFC chip via Core NFC
2. Creating SEP-53 compliant authentication messages
3. Signing messages with the chip
4. Building and submitting Stellar/Soroban transactions
5. Minting NFTs where the chip's public key becomes the token ID

## Architecture

Following the SwiftBasicPay pattern:

```
┌─────────────────────────────────────┐
│     SwiftUI Views                   │
│   • ContentView                     │
│   • MintView                        │
│   • WalletConnectView               │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│   AppData (@ObservableObject)       │
│   ┌────────────────────────────┐    │
│   │ Services:                  │    │
│   │ • NFCService               │    │
│   │ • BlockchainService        │    │
│   │ • WalletService            │    │
│   └────────────────────────────┘    │
└──────────────┬──────────────────────┘
               ↓
┌─────────────────────────────────────┐
│        Stellar SDKs                 │
│   • stellar-ios-mac-sdk             │
│   • stellar-swift-wallet-sdk        │
└─────────────────────────────────────┘
```

## Setup

### Prerequisites

- Xcode 15+ (iOS 18.0+ deployment target)
- iOS device with NFC support
- Infineon SECORA Blockchain NFC chip

### Dependencies

The app requires the following Swift Package Manager dependencies:

1. **stellar-ios-mac-sdk**
   - Repository: `https://github.com/Soneso/stellar-ios-mac-sdk`
   - Purpose: Core Stellar SDK for Horizon API, transaction building, Soroban operations

2. **stellar-swift-wallet-sdk**
   - Repository: `https://github.com/Soneso/stellar-swift-wallet-sdk`
   - Purpose: High-level wallet operations for external wallet connection

### Adding Dependencies to Xcode

1. Open `NFCBridge.xcodeproj` in Xcode
2. Select the project in the navigator
3. Go to "Package Dependencies" tab
4. Click "+" to add a package
5. Add both repositories listed above
6. Add them to the NFCBridge target

### Configuration

Edit `NFCBridge/NFCBridge/Config/Config.swift` to configure:

- **Contract ID**: Update `contractId` with your deployed contract ID
- **Network Passphrase**: Update for testnet/mainnet
- **Horizon/RPC URLs**: Update for your network
- **Recovery ID**: Defaults to 1 for Infineon chips

## Project Structure

```
NFCBridge/NFCBridge/
├── App.swift                    # App entry point
├── ContentView.swift            # Main view router
├── Model/
│   └── AppData.swift           # Observable state manager
├── Services/
│   ├── NFCService.swift        # ✅ NFC reading (already implemented)
│   ├── BlockchainService.swift # ⚠️ Stellar/Soroban operations (needs SDK)
│   └── WalletService.swift     # ⚠️ Wallet management (needs SDK)
├── Crypto/
│   ├── CryptoUtils.swift       # ✅ Hex/bytes conversions, SHA-256
│   └── SEP53.swift             # ✅ SEP-53 message creation
├── Config/
│   └── Config.swift            # ✅ Recovery ID and network config
├── Views/
│   ├── MintView.swift          # ⚠️ Mint UI (needs SDK integration)
│   └── WalletConnectView.swift # ⚠️ Wallet connection UI (needs SDK)
├── NFCService/
│   ├── NFCService.swift        # ✅ NFC tag communication
│   └── NFCSessionDelegate.swift # ✅ NFC session handling
└── APDU/
    ├── APDUCommands.swift      # ✅ SECORA APDU commands
    └── APDUHandler.swift       # ✅ Signature parsing
```

✅ = Implemented  
⚠️ = Needs SDK integration

## Implementation Status

### Completed

- ✅ NFC chip reading (public key)
- ✅ NFC chip signing (DER signature parsing)
- ✅ Crypto utilities (hex/bytes, SHA-256)
- ✅ SEP-53 message creation (matches web app)
- ✅ Recovery ID configuration (constant: 1)
- ✅ Basic UI structure (MintView, WalletConnectView)

### Pending (Requires SDK Integration)

- ⚠️ BlockchainService: Transaction building and submission
- ⚠️ WalletService: External wallet connection and manual key management
- ⚠️ Secure Enclave storage for private keys
- ⚠️ End-to-end mint flow testing

## Usage

1. **Build and Install**: Deploy to your iPhone via Xcode
2. **Connect Wallet**: 
   - Option A: Connect external wallet (Freighter, LOBSTR)
   - Option B: Enter secret key or mnemonic (stored in Secure Enclave)
3. **Mint NFT**: 
   - Tap "Mint NFT" button
   - Place NFC chip on back of iPhone
   - App reads chip, creates SEP-53 message, signs, and submits transaction
4. **Success**: Token ID = chip's public key

## Mint Flow

1. User taps "Mint NFT"
2. App prompts: "Place NFC chip on back of phone"
3. App reads chip public key via NFC
4. App creates SEP-53 message:
   - Hash network passphrase
   - Add contract ID
   - Add function name ("mint")
   - Add args (wallet address)
   - Add ledger expiry (current + 100)
5. App hashes message with SHA-256
6. App sends APDU command to chip for signature
7. App receives signature (r, s) from chip
8. App uses recovery ID 1 (constant)
9. App builds Soroban transaction (using SDK)
10. App signs transaction:
    - External wallet: Deep link to wallet app
    - Manual key: Sign locally using Secure Enclave
11. App submits signed transaction to network
12. App shows success with token ID

## Testing

To test end-to-end:

1. Ensure contract is deployed and contract ID is configured
2. Connect wallet (external or manual)
3. Have Infineon SECORA chip ready
4. Run mint flow
5. Verify same chip produces same token ID as web app

## Security

- Private keys stored in iOS Secure Enclave (hardware-backed)
- NFC chip private keys never leave the chip
- SEP-53 standard authentication
- Ledger-based expiry prevents replay attacks

## Reference

- [SwiftBasicPay](https://github.com/Soneso/SwiftBasicPay) - Architecture pattern reference
- [stellar-ios-mac-sdk](https://github.com/Soneso/stellar-ios-mac-sdk) - Stellar SDK documentation
- [stellar-swift-wallet-sdk](https://github.com/Soneso/stellar-swift-wallet-sdk) - Wallet SDK documentation
- [SEP-53](https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0053.md) - Contract authentication standard

