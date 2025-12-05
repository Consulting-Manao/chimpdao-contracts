import {
  createContext,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useTransition,
} from "react";
import { wallet } from "../util/wallet";
import storage from "../util/storage";
import { fetchBalances } from "../util/wallet";
import type { MappedBalances } from "../util/wallet";

const signTransaction = wallet.signTransaction.bind(wallet);

/**
 * A good-enough implementation of deepEqual.
 *
 * Used in this file to compare MappedBalances.
 *
 * Should maybe add & use a new dependency instead, if needed elsewhere.
 */
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

const POLL_INTERVAL = 1000;

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
  const lastSetNetworkRef = useRef<string | undefined>(undefined);

  const nullify = () => {
    setAddress(undefined);
    setNetwork(undefined);
    setNetworkPassphrase(undefined);
    setBalances({});
    addressRef.current = undefined;
    networkRef.current = undefined;
    networkForBalancesRef.current = undefined;
    lastSetNetworkRef.current = undefined;
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

    // Use wallet's network for fetching balances - normalize for consistency
    const normalizedNetwork = currentNetwork ? currentNetwork.toUpperCase() : currentNetwork;
    
    // Only fetch if network actually changed (check both normalized network and address)
    const networkKey = `${currentAddress}:${normalizedNetwork}`;
    const lastKey = networkForBalancesRef.current;
    
    if (networkKey === lastKey) {
      return; // Network and address haven't changed, skip fetch
    }
    
    networkForBalancesRef.current = networkKey;
    const newBalances = await fetchBalances(currentAddress, normalizedNetwork);
    setBalances((prev) => {
      if (deepEqual(newBalances, prev)) return prev;
      return newBalances;
    });
  }, []); // Stable callback - uses refs instead of dependencies

  // Update refs when address or network change, then trigger balance update
  useEffect(() => {
    // Normalize network for comparison and storage in ref
    const normalizedNetwork = network ? network.toUpperCase() : network;
    
    // Check if values actually changed
    const addressChanged = address !== addressRef.current;
    const networkChanged = normalizedNetwork !== networkRef.current;
    
    if (addressChanged || networkChanged) {
      addressRef.current = address;
      networkRef.current = normalizedNetwork;
      // Only update balances if we have an address
      if (address) {
        void updateBalances();
      } else {
        setBalances({});
        networkForBalancesRef.current = undefined;
      }
    }
  }, [address, network, updateBalances]);

  const updateCurrentWalletState = async () => {
    // There is no way, with StellarWalletsKit, to check if the wallet is
    // installed/connected/authorized. We need to manage that on our side by
    // checking our storage item.
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
      lastSetNetworkRef.current = normalizedStoredNetwork;
      setNetworkPassphrase(passphrase);
    }

    if (!walletId) {
      nullify();
    } else {
      if (popupLock.current) return;
      // If our storage item is there, then we try to get the user's address &
      // network from their wallet. Note: `getAddress` MAY open their wallet
      // extension, depending on which wallet they select!
      try {
        popupLock.current = true;
        wallet.setWallet(walletId);
        if (walletId !== "freighter" && walletAddr !== null) return;
        const [a, n] = await Promise.all([
          wallet.getAddress(),
          wallet.getNetwork(),
        ]);

        if (!a.address) storage.setItem("walletId", "");
        // Normalize network values for comparison to prevent oscillation
        const normalizedWalletNetwork = (n.network || "").toUpperCase();
        const normalizedCurrentNetwork = (network || "").toUpperCase();
        const lastNormalizedNetwork = (lastNetworkRef.current || "").toUpperCase();
        
        // Only update if values actually changed (using normalized comparison)
        // Check against both current state and last seen value to prevent oscillation
        const addressChanged = a.address !== address;
        const networkChanged = normalizedWalletNetwork !== "" && 
                               normalizedWalletNetwork !== normalizedCurrentNetwork && 
                               normalizedWalletNetwork !== lastNormalizedNetwork;
        const passphraseChanged = n.networkPassphrase !== networkPassphrase;
        
        if (addressChanged || networkChanged || passphraseChanged) {
          storage.setItem("walletAddress", a.address);
          if (addressChanged) {
            setAddress(a.address);
          }
          if (n.network) {
            // Store normalized network value for comparison
            const normalizedValue = n.network.toUpperCase();
            
            // Use functional setState to only update if value actually changed
            setNetwork((prevNetwork) => {
              const prevNormalized = (prevNetwork || "").toUpperCase();
              if (normalizedValue !== prevNormalized) {
                lastSetNetworkRef.current = normalizedValue;
                return normalizedValue;
              }
              // Return previous value to prevent unnecessary re-render
              return prevNetwork;
            });
            
            lastNetworkRef.current = normalizedValue;
          }
          if (passphraseChanged) setNetworkPassphrase(n.networkPassphrase);
        } else if (n.network) {
          // Update ref even if nothing changed, to track what we last saw
          const normalizedValue = n.network.toUpperCase();
          lastNetworkRef.current = normalizedValue;
        }
      } catch (e) {
        // If `getNetwork` or `getAddress` throw errors... sign the user out???
        nullify();
        // then log the error (instead of throwing) so we have visibility
        // into the error while working on Scaffold Stellar but we do not
        // crash the app process
        console.error(e);
      } finally {
        popupLock.current = false;
      }
    }
  };

  useEffect(() => {
    let timer: NodeJS.Timeout;
    let isMounted = true;

    // Create recursive polling function to check wallet state continuously
    const pollWalletState = async () => {
      if (!isMounted) return;

      await updateCurrentWalletState();

      if (isMounted) {
        timer = setTimeout(() => void pollWalletState(), POLL_INTERVAL);
      }
    };

    // Get the wallet address when the component is mounted for the first time
    startTransition(async () => {
      await updateCurrentWalletState();
      // Start polling after initial state is loaded

      if (isMounted) {
        timer = setTimeout(() => void pollWalletState(), POLL_INTERVAL);
      }
    });

    // Clear the timeout and stop polling when the component unmounts
    return () => {
      isMounted = false;
      if (timer) clearTimeout(timer);
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps -- it SHOULD only run once per component mount

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
