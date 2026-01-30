/**
 * Reusable Tabs Component
 * Provides consistent tab navigation with proper styling
 */

import { Button } from "@stellar/design-system";
import { Box } from "./Box.tsx";

interface TabItem {
  id: string;
  label: string;
}

interface TabsProps {
  tabs: TabItem[];
  activeTab: string;
  onTabChange: (tabId: string) => void;
}

export const Tabs = ({ tabs, activeTab, onTabChange }: TabsProps) => {
  return (
    <div style={{ borderBottom: "1px solid #e0e0e0", marginBottom: "24px" }}>
      <Box gap="sm" direction="row">
        {tabs.map((tab) => (
          <Button
            key={tab.id}
            type="button"
            variant={activeTab === tab.id ? "primary" : "tertiary"}
            size="md"
            onClick={() => onTabChange(tab.id)}
            style={
              activeTab === tab.id
                ? {
                    marginBottom: "-1px",
                    borderBottom: "2px solid",
                    borderBottomColor: "var(--sds-clr-primary-9, #7c3aed)",
                  }
                : undefined
            }
          >
            {tab.label}
          </Button>
        ))}
      </Box>
    </div>
  );
};
