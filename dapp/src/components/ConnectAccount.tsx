import React from "react";
import { stellarNetwork } from "../contracts/util.ts";
import FundAccountButton from "./FundAccountButton.tsx";
import { WalletButton } from "./WalletButton.tsx";
import NetworkPill from "./NetworkPill.tsx";

const ConnectAccount: React.FC = () => {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "row",
        alignItems: "center",
        gap: "10px",
        verticalAlign: "middle",
      }}
    >
      <WalletButton />
      {stellarNetwork !== "PUBLIC" && <FundAccountButton />}
      <NetworkPill />
    </div>
  );
};

export default ConnectAccount;
