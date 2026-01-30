import { getPositiveIntError } from "./getPositiveIntError.ts";
import { sanitizeObject } from "../../util/sanitizeObject.ts";
import { isEmptyObject } from "../../util/isEmptyObject.ts";
import { TimeBoundsValue } from "../../types/types.ts";

export const getTimeBoundsError = ({ min_time, max_time }: TimeBoundsValue) => {
  const validated = sanitizeObject({
    min_time: min_time
      ? getPositiveIntError(min_time.toString())
      : (false as const),
    max_time: max_time
      ? getPositiveIntError(max_time.toString())
      : (false as const),
  });

  return isEmptyObject(validated) ? false : validated;
};
