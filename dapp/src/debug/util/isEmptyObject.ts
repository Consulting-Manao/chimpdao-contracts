import { AnyObject } from "../types/types.ts";

export const isEmptyObject = (obj: AnyObject) => {
  return Object.keys(obj).length === 0;
};
