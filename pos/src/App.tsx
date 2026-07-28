import { useState } from "react";
import { AmountEntry } from "./components/AmountEntry.tsx";
import { PayStage } from "./components/PayStage.tsx";
import { Settings } from "./components/Settings.tsx";
import { useNfc } from "./hooks/useNfc.ts";
import { useMerchant } from "./hooks/useMerchant.ts";
import { usePayment } from "./hooks/usePayment.ts";

export default function App() {
  const [showSettings, setShowSettings] = useState(false);
  const nfc = useNfc();
  const { destination, setDestination } = useMerchant();
  const pay = usePayment(nfc.client, nfc.status.chipPresent, destination);

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <img src="/chimp-logo.png" alt="" />
          <span>Chi//mp</span>
        </div>
        <button
          type="button"
          className="icon-btn"
          aria-label={showSettings ? "Back to payment" : "Settings"}
          onClick={() => setShowSettings((v) => !v)}
        >
          {showSettings ? <BackIcon /> : <GearIcon />}
        </button>
      </header>

      {showSettings ? (
        <Settings
          destination={destination}
          setDestination={setDestination}
          nfc={nfc.client}
          status={nfc.status}
          connected={nfc.connected}
          nfcError={nfc.error}
          onRetry={() => void nfc.retry()}
        />
      ) : pay.phase === "idle" ? (
        <AmountEntry
          amount={pay.amount}
          symbol={pay.symbol}
          onChange={pay.setAmount}
          onPay={pay.start}
          canPay={pay.ready}
          note={destination ? undefined : "Set a merchant in Settings"}
        />
      ) : (
        <PayStage
          phase={pay.phase}
          step={pay.step}
          amount={pay.amount}
          symbol={pay.symbol}
          chipPresent={nfc.status.chipPresent}
          result={pay.result}
          error={pay.error}
          onReset={pay.reset}
          onRetry={pay.retry}
        />
      )}
    </div>
  );
}

function GearIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M10.3 2.9h3.4l.4 2a7.3 7.3 0 0 1 1.7.7l1.8-1 2.4 2.4-1 1.8c.3.5.5 1.1.7 1.7l2 .4v3.4l-2 .4c-.2.6-.4 1.2-.7 1.7l1 1.8-2.4 2.4-1.8-1a7.3 7.3 0 0 1-1.7.7l-.4 2h-3.4l-.4-2a7.3 7.3 0 0 1-1.7-.7l-1.8 1-2.4-2.4 1-1.8a7.3 7.3 0 0 1-.7-1.7l-2-.4v-3.4l2-.4c.2-.6.4-1.2.7-1.7l-1-1.8 2.4-2.4 1.8 1a7.3 7.3 0 0 1 1.7-.7l.4-2Z" />
      <circle cx="12" cy="12" r="3.2" />
    </svg>
  );
}

function BackIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M15 5l-7 7 7 7" />
    </svg>
  );
}
