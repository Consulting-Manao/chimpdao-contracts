/**
 * NFC Mint Product Component
 * Main container that orchestrates all contract operations
 * Uses tabs/sections for: Mint, Transfer, Balance
 */

import { useState, useEffect } from "react";
import { Button, Text } from "@stellar/design-system";
import { useWallet } from "../hooks/useWallet";
import { useNFC } from "../hooks/useNFC";
import { useContractId } from "../hooks/useContractId";
import { Box } from "./layout/Box";
import { ConfigurationSection } from "./ConfigurationSection";
import { NDEFOperationsSection } from "./NDEFOperationsSection";
import { KeyManagementSection } from "./KeyManagementSection";
import { MintSection } from "./contracts/MintSection";
import { TransferSection } from "./contracts/TransferSection";
import { ClaimSection } from "./contracts/ClaimSection";
import { BalanceSection } from "./contracts/BalanceSection";
import { ChipNotPresentError } from "../util/nfcClient";

type Tab = 'mint' | 'transfer' | 'claim' | 'balance';

export const NFCMintProduct = () => {
  const { address, network: walletNetwork } = useWallet();
  const { connected, connect, readNDEF, readingNDEF } = useNFC();
  const { contractId, setContractId } = useContractId(walletNetwork);
  const [selectedKeyId, setSelectedKeyId] = useState<string>("1");
  const [ndefData, setNdefData] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<Tab>('mint');

  // Auto-connect to NFC server on component mount
  useEffect(() => {
    if (!connected) {
      connect().catch(() => {
        // Server may not be running, user will connect manually
      });
    }
  }, [connected, connect]);

  const handleReadNDEF = async () => {
    if (!connected) {
      await connect();
    }

    try {
      const url = await readNDEF();
      setNdefData(url);
    } catch (err) {
      console.error('handleReadNDEF: Error:', err);
      if (err instanceof ChipNotPresentError) {
        setNdefData(null);
        alert('No NFC chip detected. Please place the chip on the reader.');
      } else {
        console.error('Failed to read NDEF:', err);
        alert(`Failed to read NDEF: ${err instanceof Error ? err.message : 'Unknown error'}`);
      }
    }
  };

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to use contract operations with NFC chip
      </Text>
    );
  }

  return (
    <Box gap="md" direction="column">
      {/* Configuration Section */}
      <ConfigurationSection
        keyId={selectedKeyId}
        contractId={contractId}
        onKeyIdChange={setSelectedKeyId}
        onContractIdChange={setContractId}
        walletNetwork={walletNetwork}
      />

      {/* Key Management Section */}
      <KeyManagementSection
        keyId={(() => {
          const parsed = parseInt(selectedKeyId, 10);
          return isNaN(parsed) ? 1 : parsed;
        })()}
      />

      {/* NDEF Operations Section */}
      <NDEFOperationsSection
        ndefData={ndefData}
        onReadNDEF={handleReadNDEF}
        readingNDEF={readingNDEF}
      />

      {/* Tab Navigation */}
      <Box gap="sm" direction="row" style={{ borderBottom: "1px solid #e0e0e0", marginBottom: "24px" }}>
        <Button
          type="button"
          variant={activeTab === 'mint' ? 'primary' : 'tertiary'}
          size="md"
          onClick={() => setActiveTab('mint')}
        >
          Mint
        </Button>
        <Button
          type="button"
          variant={activeTab === 'transfer' ? 'primary' : 'tertiary'}
          size="md"
          onClick={() => setActiveTab('transfer')}
        >
          Transfer
        </Button>
        <Button
          type="button"
          variant={activeTab === 'claim' ? 'primary' : 'tertiary'}
          size="md"
          onClick={() => setActiveTab('claim')}
        >
          Claim
        </Button>
        <Button
          type="button"
          variant={activeTab === 'balance' ? 'primary' : 'tertiary'}
          size="md"
          onClick={() => setActiveTab('balance')}
        >
          Balance
        </Button>
      </Box>

      {/* Tab Content */}
      {activeTab === 'mint' && (
        <MintSection key={`mint-${contractId}`} keyId={selectedKeyId} contractId={contractId} />
      )}
      {activeTab === 'transfer' && (
        <TransferSection key={`transfer-${contractId}`} keyId={selectedKeyId} contractId={contractId} />
      )}
      {activeTab === 'claim' && (
        <ClaimSection key={`claim-${contractId}`} keyId={selectedKeyId} contractId={contractId} />
      )}
      {activeTab === 'balance' && (
        <BalanceSection key={`balance-${contractId}`} contractId={contractId} />
      )}
    </Box>
  );
};
