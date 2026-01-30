import { use } from "react";
import {
  NotificationContext,
  NotificationContextType,
} from "../providers/NotificationProvider.tsx";

export const useNotification = (): NotificationContextType => {
  const context = use(NotificationContext);
  if (!context) {
    throw new Error(
      "useNotification must be used within a NotificationProvider",
    );
  }
  return context;
};
