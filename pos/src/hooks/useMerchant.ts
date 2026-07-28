import { useCallback, useEffect, useState } from "react";

const KEY = "chimpdao-pos-merchant";

export function useMerchant() {
  const [destination, setDestinationState] = useState(() => {
    return (
      localStorage.getItem(KEY) ||
      import.meta.env.VITE_MERCHANT_ADDRESS ||
      ""
    );
  });

  useEffect(() => {
    if (destination) localStorage.setItem(KEY, destination);
    else localStorage.removeItem(KEY);
  }, [destination]);

  const setDestination = useCallback((addr: string) => {
    setDestinationState(addr.trim());
  }, []);

  return { destination, setDestination };
}
