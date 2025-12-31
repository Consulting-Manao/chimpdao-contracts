# Privacy Policy - Chimp

**Last Updated: January 2026**  
**Effective: January 2026**

## 1. Introduction

Consulting Manao GmbH ("Company", "we", "us") operates the Chimp iOS application ("App", "Service") for the Stellar Merch Shop platform. We are committed to protecting your privacy and ensuring transparency about how we collect, use, and protect your personal data in accordance with the General Data Protection Regulation (GDPR) and Austrian data protection laws.

**Minimal Data Collection**: Our App involves minimal personal data collection. We do not operate backend servers or databases. All user data is stored locally on your device (iOS Keychain and UserDefaults) or on-chain (Stellar blockchain). We do not use analytics, tracking, or third-party data collection services.

**Contact Information**:  
Consulting Manao GmbH  
FN 571029z  
Email: legal@consulting-manao.com

## 2. Data Controller

Consulting Manao GmbH is the data controller responsible for processing your personal data in connection with the Chimp App.

## 3. Types of Data We Collect

**Important**: We do not operate backend servers or databases. All data is either:
- Stored locally on your device using iOS Keychain (encrypted, device-only) or UserDefaults (local preferences)
- Stored on-chain via the Stellar blockchain (publicly visible and permanent)
- Stored on decentralized IPFS networks (publicly accessible for NFT metadata)

### 3.1 Data You Provide Directly

**Wallet Information**:
- Stellar wallet private keys (stored in iOS Keychain, encrypted, device-only)
- Stellar wallet public addresses (stored in UserDefaults, local device storage)
- Wallet connection preferences

**App Configuration**:
- Network selection (testnet/mainnet)
- Contract ID preferences
- Admin mode settings (if applicable)

**User Responsibility**: You are responsible for ensuring your wallet keys are kept secure. We do not have access to your private keys, which are stored exclusively in your device's Keychain.

### 3.2 Data Collected Automatically

**Blockchain Data** (publicly visible on Stellar Network):
- Transaction hashes and timestamps
- Smart contract interaction data
- NFT ownership records
- Token transfer history

**NFC Chip Data** (read only, not stored):
- Chip public keys (read from NFC chips for authentication)
- Contract IDs embedded in NFC chips
- Token IDs associated with chips

**Technical Data**:
- **Device Information**: iOS version, device model (collected by Apple App Store for distribution)
- **App Usage**: No analytics or tracking. We do not collect usage patterns or user behavior data.

**Local Storage** (stored on your device only):
- **iOS Keychain**: Private keys stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (encrypted, device-only, never synced)
- **UserDefaults**: Wallet addresses, network preferences, contract IDs (local device storage, cleared when app is deleted)

**IPFS Data** (publicly accessible):
- NFT metadata and images fetched from IPFS networks
- Content Identifiers (CIDs) for NFT content
- Content metadata and timestamps

### 3.3 Data from Third-Party Services

**Stellar Network**:
- Account balances and transaction history (public blockchain data)
- Network fees and transaction status
- Account metadata

**IPFS Networks**:
- NFT metadata and images (publicly accessible content)
- Content distributed across decentralized IPFS network

## 4. Legal Basis for Processing

We process your personal data based on the following legal grounds under GDPR:

**Contract Performance (Article 6(1)(b))**: Processing necessary for providing our wallet and NFT management services, including wallet creation, NFT claiming, transferring, and signing operations.

**Legitimate Interest (Article 6(1)(f))**: Processing for app security, fraud prevention, and service functionality.

**Consent (Article 6(1)(a))**: For optional features like app configuration preferences.

**Legal Obligation (Article 6(1)(c))**: Compliance with Austrian and EU legal requirements, including anti-money laundering and sanctions screening.

**No Automated Decision-Making**: We do not engage in automated decision-making or profiling with legal effects.

## 5. How We Use Your Data

### 5.1 Service Provision

- **Wallet Management**: Creating and maintaining your Stellar wallet
- **NFT Operations**: Facilitating NFT claiming, transferring, minting, and viewing
- **NFC Authentication**: Reading NFC chips to authenticate and interact with physical merchandise
- **Blockchain Transactions**: Executing transactions on the Stellar network

### 5.2 Platform Operations

- **Security**: Protecting your wallet and transaction data
- **Support**: Providing technical support and resolving issues

### 5.3 Legal Compliance

- **Regulatory Requirements**: Complying with Austrian and EU laws
- **Sanctions Screening**: Checking against restricted jurisdiction lists
- **Audit Trail**: Maintaining records for transparency and accountability

## 6. Data Sharing and Third-Party Services

### 6.1 Third-Party Service Providers

We interact with third-party services necessary for operations:

- **Stellar Network**: Public blockchain for transaction processing
- **IPFS Networks**: Decentralized storage for NFT metadata
- **Apple App Store**: Distribution and device information (collected by Apple)

**No Data Processing Agreements Required**: We do not share personal data with third-party processors. All data remains on your device or on public blockchains.

### 6.2 No Backend Data Storage

We do not store any user data on our own servers. All data exists on:
- Your device's iOS Keychain (encrypted, device-only)
- Your device's UserDefaults (local preferences)
- The Stellar blockchain (permanent, public, immutable)
- IPFS networks (distributed, public, persistent)

### 6.3 Legal Requirements

We may disclose your data when required by law, including:

- Compliance with Austrian or EU legal obligations
- Response to valid legal requests from authorities
- Protection of our rights and the rights of other users
- Prevention of fraud or illegal activities

### 6.4 No Sale of Data

We do not sell, rent, or trade your personal data to third parties for commercial purposes.

## 7. Data Security

### 7.1 Security Measures

We implement appropriate technical and organizational measures to protect your data:

- **iOS Keychain Encryption**: Private keys stored using iOS Keychain Services with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (encrypted, device-only, never synced to iCloud)
- **No Network Transmission**: Private keys never leave your device
- **Access Controls**: Limited access to personal data on a need-to-know basis
- **Secure Coding Practices**: Following iOS security best practices

### 7.2 Blockchain Security

- **Non-Custodial**: We do not store or have access to your private keys
- **Device-Only Storage**: Private keys exist only in your device's Keychain
- **Public Transparency**: Blockchain transactions are publicly verifiable

### 7.3 NFC Security

- **Read-Only Operations**: We only read data from NFC chips, never write or store chip data
- **Local Processing**: All NFC operations occur locally on your device
- **No Chip Data Storage**: Chip public keys and identifiers are not stored after use

### 7.4 Data Breach Response

In the event of a data breach (though we operate no backend servers), we will notify relevant authorities within 72 hours (GDPR Article 33) and inform affected users without undue delay (GDPR Article 34).

## 8. Your Rights Under GDPR

You have the following rights regarding your personal data:

### 8.1 Right of Access (Article 15)

You can request information about the personal data we process about you, including:

- Categories of data processed
- Purposes of processing
- Recipients of your data
- Retention periods
- Your rights regarding the data

### 8.2 Right to Rectification (Article 16)

You can request correction of inaccurate or incomplete personal data.

### 8.3 Right to Erasure (Article 17)

You can request deletion of your personal data in certain circumstances, including:

- Data no longer necessary for original purposes
- Withdrawal of consent
- Unlawful processing
- Objection to processing

**Technical Limitations**:
- **Blockchain Data**: Permanently recorded and immutable (GDPR Article 17(3)(b) exception for data made public by the data subject)
- **IPFS Content**: Cannot be deleted once uploaded to the decentralized IPFS network
- **Local Device Data**: You can delete all local data by uninstalling the app, which removes:
  - All data from iOS Keychain (private keys)
  - All data from UserDefaults (wallet addresses, preferences)

**User Control**: You can delete your wallet and all local app data at any time by:
- Using the "Delete Wallet" function in the app settings
- Uninstalling the app (removes all local data)

### 8.4 Right to Restrict Processing (Article 18)

You can request limitation of data processing in certain situations.

### 8.5 Right to Data Portability (Article 20)

You can request a copy of your data in a structured, machine-readable format. Note: Private keys cannot be exported for security reasons, but you can export your wallet address and transaction history.

### 8.6 Right to Object (Article 21)

You can object to processing based on legitimate interests or for direct marketing purposes.

### 8.7 Rights Related to Automated Decision-Making (Article 22)

You have rights regarding automated decision-making, though our App does not use automated decision-making for individual users.

## 9. Exercising Your Rights

To exercise your rights, contact us at:

**Email**: legal@consulting-manao.com  
**Subject**: Data Protection Request - Chimp App

We will respond to your request within one month (GDPR Article 12(3)). We may request verification of your identity to protect your privacy.

## 10. Data Retention and Deletion

**Blockchain Data**: Permanently recorded (GDPR Article 17(3)(b) exception for data made public by the data subject).

**IPFS Content**: Persists indefinitely on decentralized network; we cannot delete once uploaded.

**Local Device Data**:
- **iOS Keychain**: Retained until you delete the wallet or uninstall the app
- **UserDefaults**: Retained until you clear app data or uninstall the app
- **Uninstall**: Removing the app deletes all local data (Keychain and UserDefaults)

**Tax Records**: 7 years per Austrian Federal Fiscal Code (BAO) §132 and §212, if applicable.

**Deletion Limitations**: Blockchain and IPFS data cannot be deleted. We can only help you understand how to manage your local device data.

## 11. International Data Transfers

### 11.1 Data Transfers

Your data may be transferred to and processed in countries outside the EU/EEA, including:

- **IPFS Networks**: Global decentralized storage networks
- **Stellar Network**: Distributed blockchain network
- **Apple Services**: United States-based service provider (App Store, device information)

### 11.2 Safeguards

We ensure appropriate safeguards for international transfers through adequacy decisions, standard contractual clauses where applicable, and technical measures (iOS Keychain encryption).

## 12. NFC Functionality

### 12.1 NFC Permissions

The App requires NFC (Near Field Communication) access to:
- Read data from NFC chips embedded in physical merchandise
- Authenticate chip public keys for NFT operations
- Read contract IDs and token information from chips

### 12.2 NFC Data Handling

- **Read-Only**: We only read data from NFC chips; we do not write data to chips
- **No Storage**: Chip data (public keys, contract IDs) is not stored after use
- **Local Processing**: All NFC operations occur locally on your device
- **Privacy**: NFC chip data is used only for authentication and is not shared with third parties

### 12.3 NFC Usage Description

The App displays "Allow to scan tags" when requesting NFC access.

## 13. iOS Keychain and Local Storage

### 13.1 Keychain Storage

Private keys are stored in iOS Keychain with the following security settings:
- **Accessibility**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **Encryption**: Encrypted by iOS using device-specific keys
- **Device-Only**: Never synced to iCloud or other devices
- **Access Control**: Requires device unlock to access

### 13.2 UserDefaults Storage

App preferences are stored in UserDefaults (local device storage):
- Wallet public addresses
- Network selection (testnet/mainnet)
- Contract ID preferences
- Admin mode settings

**Deletion**: All UserDefaults data is deleted when you uninstall the app.

### 13.3 No Tracking or Analytics

We do not use:
- Analytics services
- Tracking technologies
- Third-party data collection
- Advertising identifiers

## 14. Children's Privacy

Our services are not intended for children under 18. We do not knowingly collect personal data from children under 18. If we become aware that we have collected data from a child under 18, we will take steps to delete such information.

## 15. Changes to This Privacy Policy

### 15.1 Updates

We may update this Privacy Policy to reflect:

- Changes in our data processing practices
- New legal requirements
- App feature updates
- Security improvements

### 15.2 Notification

We will notify you of significant changes by:

- Posting the updated policy in the App (if applicable)
- Updating the "Last Updated" date
- Displaying notices in the App

### 15.3 Continued Use

Continued use of our App after policy updates constitutes acceptance of the new terms.

## 16. Data Protection Officer

As a small GmbH, we are not required to appoint a Data Protection Officer under GDPR Article 37, but privacy inquiries can be directed to legal@consulting-manao.com.

**Why No DPO Required**: Under GDPR Article 37(1), DPO appointment is mandatory only for public authorities or organizations with large-scale processing. Our App operates with minimal data collection and no backend storage, thus not meeting these thresholds.

## 17. Supervisory Authority

You have the right to lodge a complaint with the Austrian Data Protection Authority:

**Austrian Data Protection Authority**  
Barichgasse 40-42  
1030 Vienna, Austria  
Website: [dsb.gv.at](https://dsb.gv.at)

## 18. Contact Information

For any questions about this Privacy Policy or our data practices:

**Consulting Manao GmbH**  
Registered in Austrian Commercial Register (Firmenbuch)  
Landesgericht Graz, FN 571029z  
VAT ID: ATU77780135  
Managing Director: Pamphile Tupui Christophe Roy

**Contact**:  
Email: legal@consulting-manao.com

**Last Updated**: January 2026

