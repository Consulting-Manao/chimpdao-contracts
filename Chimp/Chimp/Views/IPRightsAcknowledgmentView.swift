import SwiftUI

struct IPRightsAcknowledgmentView: View {
    @Binding var isPresented: Bool
    @State private var hasAcknowledged: Bool = false
    
    let onAcknowledged: () -> Void
    
    private let ipRightsContent: String = IPRightsContent.text
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Document content (markdown parser handles the title from first # header)
                    IPRightsContentView(content: ipRightsContent)
                    
                    // Acknowledgment section at bottom of content
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                            .padding(.vertical, 8)
                        
                        Toggle(isOn: $hasAcknowledged) {
                            Text("I have read and agree to the Intellectual Property Rights & Licensing Guidelines")
                                .font(.subheadline)
                        }
                        .accessibilityLabel("Acknowledge IP rights")
                        .accessibilityHint("Check this box to acknowledge you have read and agree to the IP rights guidelines")
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Continue") {
                        onAcknowledged()
                        isPresented = false
                    }
                    .disabled(!hasAcknowledged)
                    .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// Helper view to render markdown content
struct IPRightsContentView: View {
    let content: String
    @State private var formattedContent: [TextSegment] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(formattedContent.enumerated()), id: \.offset) { index, segment in
                segment.view
            }
        }
        .onAppear {
            formattedContent = parseMarkdown(content)
        }
    }
}

// Data structure for parsed markdown segments
struct TextSegment {
    let type: SegmentType
    let text: String
    
    enum SegmentType {
        case title1
        case title2
        case title3
        case body
        case listItem
        case emptyLine
    }
    
    var view: some View {
        Group {
            switch type {
            case .title1:
                Text(text)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 8)
            case .title2:
                Text(text)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.top, 8)
            case .title3:
                Text(text)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding(.top, 6)
            case .body:
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            case .listItem:
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.body)
                    Text(text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            case .emptyLine:
                Text("")
                    .frame(height: 8)
            }
        }
    }
}

// Simple markdown parser
func parseMarkdown(_ content: String) -> [TextSegment] {
    var segments: [TextSegment] = []
    let lines = content.components(separatedBy: .newlines)
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.isEmpty {
            segments.append(TextSegment(type: .emptyLine, text: ""))
            continue
        }
        
        // Remove markdown bold syntax (**text** -> text)
        let processedText = trimmed.replacingOccurrences(of: "**", with: "")
        
        // Check for headers
        if trimmed.hasPrefix("### ") {
            let text = String(processedText.dropFirst(4))
            segments.append(TextSegment(type: .title3, text: text))
        } else if trimmed.hasPrefix("## ") {
            let text = String(processedText.dropFirst(3))
            segments.append(TextSegment(type: .title2, text: text))
        } else if trimmed.hasPrefix("# ") {
            let text = String(processedText.dropFirst(2))
            segments.append(TextSegment(type: .title1, text: text))
        } else if trimmed.hasPrefix("- ") {
            // List item
            let text = String(processedText.dropFirst(2))
            segments.append(TextSegment(type: .listItem, text: text))
        } else {
            // Regular body text
            segments.append(TextSegment(type: .body, text: processedText))
        }
    }
    
    return segments
}

// IP Rights content constant - embedded document
struct IPRightsContent {
    static let text = """
# Intellectual Property Rights & Licensing Guidelines

**Last Updated: January 2026**  
**Effective: January 2026**

## 1. Introduction

Consulting Manao GmbH ("Company", "we", "us", "our") operates the ChimpDAO platform, which creates Non-Fungible Tokens (NFTs) on the Stellar blockchain that are permanently linked to physical apparel through embedded NFC chips. These NFTs and physical items are inseparable by design.

**Contact Information**:  
Consulting Manao GmbH  
FN 571029z  
Email: legal@consulting-manao.com

**Related Documents**: For information about data privacy, please see our Privacy Policy.

## 2. License Overview

When you own a ChimpDAO NFT, you hold a limited license to use the NFT and associated artwork for both personal and commercial purposes, subject to the terms and restrictions outlined below. This license is granted only while you own the NFT on the Stellar blockchain.

**Community Access**: Holding a ChimpDAO NFT grants you access to the ChimpDAO community and is the exclusive means of accessing said community. This access is tied to your ownership of the NFT on the Stellar blockchain and transfers with NFT ownership.

**No Financial Returns**: ChimpDAO NFTs are collectibles and community access tokens. They are not investment vehicles, securities, or financial instruments. No monetary returns or financial returns are expected from holding a ChimpDAO NFT. These NFTs are provided for collectible and community access purposes only, not for investment purposes.

### 2.1 Unique Characteristics

**Physical-Digital Binding**: Your NFT is cryptographically bound to a physical apparel item via an embedded NFC chip. The NFT and physical item cannot be separated. Any transfer, sale, or use of the NFT inherently relates to the physical item it represents.

**Stellar Blockchain**: All NFTs in this collection exist exclusively on the Stellar blockchain. This is the only blockchain where these NFTs are valid and recognized.

## 3. Personal Use

You are granted a limited, worldwide, non-exclusive license to use your specific NFT and associated artwork for personal, non-commercial purposes, including:

- Displaying the NFT artwork on social media
- Using the NFT artwork as a profile picture or avatar
- Displaying the physical apparel item in personal spaces
- Creating personal art or modifications for your own enjoyment
- Sharing images of the NFT or physical item for non-commercial purposes

**Important**: You must maintain all copyright and proprietary notices intact during such uses.

## 4. Commercial Use

Commercial use rights are granted subject to the restrictions set forth below. Holders may use their NFT and associated artwork for commercial purposes, including:

- Creating and selling physical merchandise featuring your NFT artwork
- Creating and selling digital products featuring your NFT artwork
- Using the NFT artwork in advertising and marketing materials for your business
- Incorporating the NFT artwork into films, video games, or other media
- Selling products or services that feature or reference your NFT

### 4.1 Commercial Use Restrictions

**Revenue Notification**: If your annual gross revenue from commercial activities using your NFT exceeds $100,000, you must notify us within 30 days of anticipating this threshold. This allows us to discuss a broader license agreement or potential collaboration opportunities.

**Licensing Agreements**: If you plan to enter into licensing agreements with third parties that involve your NFT, you must notify us in advance. This ensures compliance with these guidelines and allows us to explore potential support or collaboration.

**Brand Usage**: You may NOT use the "ChimpDAO" name or any associated logos, trademarks, or service marks in connection with your commercial activities without our explicit written permission. You may only factually reference the collection name when listing your NFT for sale or for non-commercial descriptive purposes.

**Prohibited Uses**: The following commercial uses are strictly prohibited:

- Using the NFT or artwork in connection with illegal activities
- Using the NFT or artwork to promote hate speech, discrimination, or violence
- Using the NFT or artwork in connection with gambling, adult content, or other activities that could damage our brand reputation
- Creating counterfeit or unauthorized merchandise that could be confused with official ChimpDAO products
- Using the NFT or artwork in a manner that falsely suggests endorsement or affiliation with ChimpDAO or Consulting Manao GmbH

## 5. Brand Protection & NFT Revocation

### 5.1 Right to Revoke License

We reserve the right to revoke the license granted under these guidelines and to burn (permanently destroy) your NFT on the Stellar blockchain if:

- You separate the NFC chip from the physical apparel item, tamper with the chip, or attempt to modify the cryptographic binding between the chip and the NFT, and such tampering is observed during the sign/claim process or verification procedures
- You use the NFT or artwork in a manner that harms our brand, reputation, or community
- You use the NFT or artwork in connection with fraudulent, deceptive, or illegal activities
- You use the NFT or artwork to promote scams, phishing, or other harmful activities
- You violate any of the commercial use restrictions outlined in Section 4.1, including but not limited to unauthorized brand usage, prohibited uses, or failure to notify us of revenue thresholds or licensing agreements
- You violate any of the restrictions outlined in these guidelines
- You engage in activities that could be considered "scam" or "scammer" behavior as determined by us in our sole discretion

**Note**: Burning an NFT on the Stellar blockchain is a permanent, irreversible action. If your NFT is burned, you will lose all rights associated with it, though the physical apparel item itself will remain in your possession.

### 5.2 Warning System

Before burning an NFT, we will typically provide a warning and opportunity to cure the violation, except in cases of egregious violations that pose immediate harm to our brand or community.

## 6. Physical Apparel & NFT Relationship

### 6.1 Inseparable Nature

The NFT and physical apparel item are designed to be inseparable. The NFC chip embedded in the apparel contains cryptographic keys that bind it to the NFT on the Stellar blockchain. This relationship is fundamental to the product's design and value proposition.

### 6.2 Transfer of Ownership

When you transfer ownership of the NFT on the Stellar blockchain, you are inherently transferring the associated rights to the physical apparel item. The license to use the NFT artwork transfers with the NFT ownership. The new owner has the same rights (personal and commercial use) as the previous owner, subject to these guidelines. The new owner has the right to claim the physical item if it has not yet been delivered, or to use the NFT as described in these guidelines.

### 6.3 Loss or Destruction of Physical Item

If the physical apparel item is lost, stolen, or destroyed, the NFT remains valid on the Stellar blockchain. However, the unique value proposition of the inseparable physical-digital pair may be diminished. We are not responsible for lost, stolen, or destroyed physical items.

### 6.4 Chip Integrity and Tampering

The NFC chip must remain embedded in the physical apparel item at all times. The cryptographic binding between the chip and the NFT on the Stellar blockchain is fundamental to the product's design and value proposition.

**Tampering Consequences**: Any attempt to separate the NFC chip from the physical apparel item, tamper with the chip, modify the chip's cryptographic keys, or damage the chip that is observed during the sign/claim process will result in the voiding of the NFT and its immediate burning on the Stellar blockchain. Tampering can only be proven if observed during the sign/claim process or other verification procedures. The chip and physical item must remain together as originally manufactured.

**Detection**: We reserve the right to verify chip integrity and detect tampering through technical means during sign/claim processes or verification procedures. Any evidence of chip separation, modification, or tampering observed during such processes will result in NFT revocation and burning.

**Note**: The physical-digital binding is essential to the NFT's validity. Maintaining the integrity of this binding is your responsibility as the NFT holder. Tampering can only be definitively proven through observation during verification processes, not through automatic assumption.

### 6.5 Proof of Ownership Requirements

Some community events, exclusive access opportunities, or participation requirements may require proof of ownership of both the NFT and the associated physical apparel item with embedded NFC chip.

**Verification Requirements**: When proof of ownership is required, you may be asked to demonstrate ownership of:
- The NFT on the Stellar blockchain (wallet ownership)
- The physical apparel item with its embedded NFC chip (through chip verification)

**Consequences of Failure to Provide Proof**: Failure to provide required proof of ownership when requested for events or participation may result in consequences, including but not limited to denial of access, exclusion from events, or other restrictions. Such consequences are determined on a case-by-case basis and do not necessarily result in NFT burning.

**Note**: Proof of ownership requirements are used to ensure the integrity of community access and to verify that holders have both the digital NFT and the physical item as intended. These requirements help maintain the inseparable nature of the physical-digital binding.

## 7. Intellectual Property Ownership

### 7.1 What We Own

We own and retain all rights, title, and interest in:

- The "ChimpDAO" name, logos, and trademarks
- The overall collection design and aesthetic
- The smart contract code and technology
- Any official marketing materials, websites, or brand assets

### 7.2 What You Own

You own the NFT as a digital asset on the Stellar blockchain. You own the license to use the specific NFT artwork associated with your NFT as described in these guidelines. You do NOT own the underlying intellectual property rights in the artwork itself.

## 8. Operational Fees

### 8.1 Fees Overview

Certain operations involving ChimpDAO NFTs may be subject to operational fees, including but not limited to:

- **Transfer Royalties**: Transfer royalties may apply to secondary sales or transfers of NFTs. These royalties are operational fees associated with the transfer mechanism and are not investment returns.
- **Commission Fees**: Commission fees may apply to transactions or operations on the platform. These fees cover operational costs and are not investment returns.
- **Network Fees**: Standard blockchain network fees apply to transactions on the Stellar blockchain. These fees are determined by the Stellar network and are not controlled by us.

### 8.2 Fee Changes

All fees, including transfer royalties and commission fees, may be changed according to applicable laws, regulations, or business requirements. We reserve the right to modify fee structures at any time to comply with applicable laws and regulations, including but not limited to EU regulations (such as MICA), Austrian law, and other relevant regulatory requirements.

**Fee Disclosure**: Applicable fees will be disclosed before transactions are completed. You will be informed of all relevant fees before executing any operation involving your NFT.

**Note**: All fees are operational costs related to the functioning of the platform and blockchain infrastructure. These fees are not investment returns or financial returns, and they do not affect the classification of ChimpDAO NFTs as collectibles and community access tokens.

## 9. No Guarantees or Warranties

THE NFT, ARTWORK, AND ASSOCIATED LICENSES ARE PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED. WE DISCLAIM ALL WARRANTIES, INCLUDING BUT NOT LIMITED TO MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

## 10. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS OR REVENUES, WHETHER INCURRED DIRECTLY OR INDIRECTLY, OR ANY LOSS OF DATA, USE, GOODWILL, OR OTHER INTANGIBLE LOSSES RESULTING FROM YOUR USE OF THE NFT OR ARTWORK.

## 11. Modifications to These Guidelines

We reserve the right to modify these guidelines at any time. Material changes will be communicated to NFT holders through reasonable means (e.g., website update, email notification). Your continued use of the NFT after such modifications constitutes acceptance of the updated guidelines.

## 12. Dispute Resolution

### 12.1 Mediation Through Tansu DAO

In the event of any dispute arising from these guidelines or your use of the NFT, the parties agree to first attempt to resolve the dispute through mediation via the Tansu DAO governance process. The Tansu DAO provides a decentralized mechanism for dispute resolution through community governance.

### 12.2 Court Jurisdiction

If mediation through Tansu DAO fails or is unavailable, or if the parties cannot reach a resolution through DAO mediation, any disputes shall be resolved in the courts of Austria.

## 13. Governing Law

These guidelines are governed by the laws of Austria, without regard to conflict of law principles.

## 14. Contact & Questions

For questions about these guidelines or to report potential violations, please contact us at:

**Email**: legal@consulting-manao.com  
**Company**: Consulting Manao GmbH  
**FN**: 571029z

## 15. Acknowledgment

By purchasing, claiming, or using a ChimpDAO NFT, you acknowledge that you have read, understood, and agree to be bound by these Intellectual Property Rights and Licensing Guidelines.

---

© 2026 Consulting Manao GmbH. All rights reserved.
"""
}
