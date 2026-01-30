/**
 * Balance Section Component
 * Displays user's NFT balance and owned tokens
 */

import { useState, useEffect } from "react";
import { Button, Text } from "@stellar/design-system";
import { Box } from "../layout/Box.tsx";
import { useWallet } from "../../hooks/useWallet.ts";
import { useContractClient } from "../../hooks/useContractClient.ts";
import type { ContractCallOptions } from "../../types/contract.ts";

interface BalanceSectionProps {
  contractId: string;
}

export const BalanceSection = ({ contractId }: BalanceSectionProps) => {
  const { address } = useWallet();
  const { contractClient, isReady } = useContractClient(contractId);
  const [balance, setBalance] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchBalance = async () => {
    if (!address || !isReady || !contractClient) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const tx = await contractClient.balance(
        {
          owner: address,
        },
        {
          publicKey: address,
        } as ContractCallOptions,
      );

      // Simulate to get the result without sending a transaction
      const simulation = await tx.simulate();
      const result = simulation.result;

      const balanceValue =
        typeof result === "bigint"
          ? Number(result)
          : typeof result === "number"
            ? result
            : Number(result);
      setBalance(balanceValue);
    } catch (err) {
      console.error("Balance fetch error:", err);
      let errorMessage = "Unknown error";
      if (err instanceof Error) {
        errorMessage = err.message || String(err);
      } else {
        errorMessage = String(err) || "Failed to fetch balance";
      }
      setError(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (address && isReady) {
      void fetchBalance();
    }
  }, [address, isReady, contractId]);

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to view your NFT balance
      </Text>
    );
  }

  return (
    <Box gap="sm" direction="column">
      <Text as="p" size="md" weight="semi-bold">
        Your NFT Balance
      </Text>

      {loading ? (
        <Text as="p" size="sm" style={{ color: "#666" }}>
          Loading balance...
        </Text>
      ) : error ? (
        <Box gap="xs" direction="column">
          <Text as="p" size="sm" style={{ color: "#d32f2f" }}>
            Error:{" "}
            {typeof error === "string"
              ? error
              : String(error || "Unknown error")}
          </Text>
          <Button
            type="button"
            variant="secondary"
            size="sm"
            onClick={fetchBalance}
          >
            Retry
          </Button>
        </Box>
      ) : balance !== null ? (
        <Box gap="xs" direction="column">
          <Text
            as="p"
            size="lg"
            weight="semi-bold"
            style={{ color: "#4caf50" }}
          >
            {balance} NFT{balance !== 1 ? "s" : ""}
          </Text>
          <Button
            type="button"
            variant="tertiary"
            size="sm"
            onClick={fetchBalance}
            style={{ marginTop: "8px" }}
          >
            Refresh Balance
          </Button>
        </Box>
      ) : (
        <Text as="p" size="sm" style={{ color: "#666" }}>
          Click refresh to load your balance
        </Text>
      )}

      {!isReady && (
        <Text as="p" size="xs" style={{ color: "#ff9800", marginTop: "8px" }}>
          Contract client not ready. Please check your contract ID.
        </Text>
      )}
    </Box>
  );
};
