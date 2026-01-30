import React from "react";
import { Layout, Text } from "@stellar/design-system";
import { NFCMintProduct } from "../components/NFCMintProduct.tsx";

const Home: React.FC = () => (
  <Layout.Content>
    <Layout.Inset>
      <Text as="h1" size="xl">
        Welcome to the Stellar Merch Shop app!
      </Text>
      <Text as="p" size="md">
        This app integrates with NFC chips to mint NFTs linked to physical
        products. Place your chip on the reader to get started.
      </Text>
      <NFCMintProduct />
    </Layout.Inset>
  </Layout.Content>
);

export default Home;
