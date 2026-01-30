import {
  createContext,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useTransition,
} from "react";
import { wallet } from "../util/wallet.ts";
import storage from "../util/storage.ts";
import { fetchBalances } from "../util/wallet.ts";
import type { MappedBalances } from "../util/wallet.ts";

const signTransaction = wallet.signTransaction.bind(wallet);

function deepEqual<T>(a: T, b: T): boolean {
  if (a === b) {
    return true;
  }

  const bothAreObjects =
    a && b && typeof a === "object" && typeof b === "object";

  return Boolean(
    bothAreObjects &&
    Object.keys(a).length === Object.keys(b).length &&
    Object.entries(a).every(([k, v]) => deepEqual(v, b[k as keyof T])),
  );
}

export interface WalletContextType {
  address?: string;
  balances: MappedBalances;
  isPending: boolean;
  network?: string;
  networkPassphrase?: string;
  signTransaction: typeof wallet.signTransaction;
  updateBalances: () => Promise<void>;
}

export const WalletContext = // eslint-disable-line react-refresh/only-export-components
  createContext<WalletContextType>({
    isPending: true,
    balances: {},
    updateBalances: async () => {},
    signTransaction,
  });

export const WalletProvider = ({ children }: { children: React.ReactNode }) => {
  const [balances, setBalances] = useState<MappedBalances>({});
  const [address, setAddress] = useState<string>();
  const [network, setNetwork] = useState<string>();
  const [networkPassphrase, setNetworkPassphrase] = useState<string>();
  const [isPending, startTransition] = useTransition();
  const popupLock = useRef(false);
  const lastNetworkRef = useRef<string | undefined>(undefined);
  const networkForBalancesRef = useRef<string | undefined>(undefined);
  const addressRef = useRef<string | undefined>(undefined);
  const networkRef = useRef<string | undefined>(undefined);

  const nullify = () => {
    setAddress(undefined);
    setNetwork(undefined);
    setNetworkPassphrase(undefined);
    setBalances({});
    addressRef.current = undefined;
    networkRef.current = undefined;
    networkForBalancesRef.current = undefined;
    storage.setItem("walletId", "");
    storage.setItem("walletAddress", "");
    storage.setItem("walletNetwork", "");
    storage.setItem("networkPassphrase", "");
  };

  const updateBalances = useCallback(async () => {
    const currentAddress = addressRef.current;
    const currentNetwork = networkRef.current;

    if (!currentAddress) {
      setBalances({});
      networkForBalancesRef.current = undefined;
      return;
    }

    const normalizedNetwork = currentNetwork
      ? currentNetwork.toUpperCase()
      : currentNetwork;
    const networkKey = `${currentAddress}:${normalizedNetwork}`;
    const lastKey = networkForBalancesRef.current;

    if (networkKey === lastKey) {
      return;
    }

    networkForBalancesRef.current = networkKey;
    const newBalances = await fetchBalances(currentAddress, normalizedNetwork);
    setBalances((prev) => {
      if (deepEqual(newBalances, prev)) return prev;
      return newBalances;
    });
  }, []);

  useEffect(() => {
    const normalizedNetwork = network ? network.toUpperCase() : network;
    const addressChanged = address !== addressRef.current;
    const networkChanged = normalizedNetwork !== networkRef.current;

    if (addressChanged || networkChanged) {
      addressRef.current = address;
      networkRef.current = normalizedNetwork;
      if (address) {
        void updateBalances();
      } else {
        setBalances({});
        networkForBalancesRef.current = undefined;
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address, network]);

  const updateCurrentWalletState = async () => {
    const walletId = storage.getItem("walletId");
    const walletNetwork = storage.getItem("walletNetwork");
    const walletAddr = storage.getItem("walletAddress");
    const passphrase = storage.getItem("networkPassphrase");

    if (
      !address &&
      walletAddr !== null &&
      walletNetwork !== null &&
      passphrase !== null
    ) {
      // Normalize network value when loading from storage to keep it consistent
      const normalizedStoredNetwork = walletNetwork.toUpperCase();
      setAddress(walletAddr);
      setNetwork(normalizedStoredNetwork);
      addressRef.current = walletAddr;
      networkRef.current = normalizedStoredNetwork;
      lastNetworkRef.current = normalizedStoredNetwork;
      setNetworkPassphrase(passphrase);
    }

    if (!walletId) {
      nullify();
    } else {
      if (popupLock.current) return;
      try {
        popupLock.current = true;
        wallet.setWallet(walletId);
        if (walletId !== "freighter" && walletAddr !== null) return;
        const [a, n] = await Promise.all([
          wallet.getAddress(),
          wallet.getNetwork(),
        ]);

        if (!a.address) storage.setItem("walletId", "");
        const normalizedWalletNetwork = (n.network || "").toUpperCase();
        const normalizedCurrentNetwork = (network || "").toUpperCase();
        const lastNormalizedNetwork = (
          lastNetworkRef.current || ""
        ).toUpperCase();

        const addressChanged = a.address !== address;
        const networkChanged =
          normalizedWalletNetwork !== "" &&
          normalizedWalletNetwork !== normalizedCurrentNetwork &&
          normalizedWalletNetwork !== lastNormalizedNetwork;
        const passphraseChanged = n.networkPassphrase !== networkPassphrase;

        if (addressChanged || networkChanged || passphraseChanged) {
          storage.setItem("walletAddress", a.address);
          if (addressChanged) {
            setAddress(a.address);
          }
          if (networkChanged && n.network) {
            const normalizedValue = n.network.toUpperCase();
            setNetwork(normalizedValue);
            lastNetworkRef.current = normalizedValue;
          }
          if (passphraseChanged) setNetworkPassphrase(n.networkPassphrase);
        }

        if (n.network) {
          const normalizedValue = n.network.toUpperCase();
          lastNetworkRef.current = normalizedValue;
        }
      } catch (e) {
        nullify();
        console.error(e);
      } finally {
        popupLock.current = false;
      }
    }
  };

  useEffect(() => {
    startTransition(async () => {
      await updateCurrentWalletState();
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const contextValue = useMemo(
    () => ({
      address,
      network,
      networkPassphrase,
      balances,
      updateBalances,
      isPending,
      signTransaction,
    }),
    [address, network, networkPassphrase, balances, updateBalances, isPending],
  );

  return <WalletContext value={contextValue}>{children}</WalletContext>;
};
