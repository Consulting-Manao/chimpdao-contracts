/**
 * NFC Mint Product Component
 * Main container that orchestrates all contract operations
 * Uses tabs/sections for: Mint, Transfer, Claim, Balance
 */

import { useState, useEffect } from "react";
import { Text } from "@stellar/design-system";
import { useWallet } from "../hooks/useWallet.ts";
import { useNFC } from "../hooks/useNFC.ts";
import { useContractId } from "../hooks/useContractId.ts";
import { useNotification } from "../hooks/useNotification.ts";
import { Box } from "./layout/Box.tsx";
import { Tabs } from "./layout/Tabs.tsx";
import { ConfigurationSection } from "./ConfigurationSection.tsx";
import { NDEFOperationsSection } from "./NDEFOperationsSection.tsx";
import { KeyManagementSection } from "./KeyManagementSection.tsx";
import { MintSection } from "./contracts/MintSection.tsx";
import { TransferSection } from "./contracts/TransferSection.tsx";
import { ClaimSection } from "./contracts/ClaimSection.tsx";
import { BalanceSection } from "./contracts/BalanceSection.tsx";
import { ChipNotPresentError } from "../util/nfcClient.ts";

type TabId = "mint" | "transfer" | "claim" | "balance";

const TABS: Array<{ id: TabId; label: string }> = [
  { id: "mint", label: "Mint" },
  { id: "transfer", label: "Transfer" },
  { id: "claim", label: "Claim" },
  { id: "balance", label: "Balance" },
];

/**
 * Parse key ID string to number, defaulting to 1 for invalid inputs
 */
const parseKeyId = (keyId: string): number => {
  const parsed = parseInt(keyId, 10);
  return isNaN(parsed) ? 1 : parsed;
};

export const NFCMintProduct = () => {
  const { address, network: walletNetwork } = useWallet();
  const { connected, connect, readNDEF, readingNDEF } = useNFC();
  const { contractId, setContractId } = useContractId(walletNetwork);
  const { addNotification } = useNotification();
  const [selectedKeyId, setSelectedKeyId] = useState<string>("1");
  const [ndefData, setNdefData] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<TabId>("mint");

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
      if (url) {
        addNotification("NDEF data read successfully", "success");
      }
    } catch (err) {
      setNdefData(null);

      const errorMessage =
        err instanceof ChipNotPresentError
          ? "No NFC chip detected. Please place the chip on the reader."
          : `Failed to read NDEF: ${err instanceof Error ? err.message : "Unknown error"}`;

      addNotification(errorMessage, "error");
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
      <KeyManagementSection keyId={parseKeyId(selectedKeyId)} />

      {/* NDEF Operations Section */}
      <NDEFOperationsSection
        ndefData={ndefData}
        onReadNDEF={handleReadNDEF}
        readingNDEF={readingNDEF}
      />

      {/* Tab Navigation */}
      <Tabs
        tabs={TABS}
        activeTab={activeTab}
        onTabChange={(tabId) => setActiveTab(tabId as TabId)}
      />

      {/* Tab Content */}
      {activeTab === "mint" && (
        <MintSection
          key={`mint-${contractId}`}
          keyId={selectedKeyId}
          contractId={contractId}
        />
      )}
      {activeTab === "transfer" && (
        <TransferSection
          key={`transfer-${contractId}`}
          keyId={selectedKeyId}
          contractId={contractId}
        />
      )}
      {activeTab === "claim" && (
        <ClaimSection
          key={`claim-${contractId}`}
          keyId={selectedKeyId}
          contractId={contractId}
        />
      )}
      {activeTab === "balance" && (
        <BalanceSection key={`balance-${contractId}`} contractId={contractId} />
      )}
    </Box>
  );
};
