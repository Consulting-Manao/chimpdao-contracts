import { isEmptyObject } from "../../util/isEmptyObject.ts";
import { getAssetCodeError } from "./getAssetCodeError.ts";
import { getPublicKeyError } from "./getPublicKeyError.ts";
import { AssetObjectValue } from "../../types/types.ts";
import { sanitizeArray } from "../../util/sanitizeArray.ts";

export const getAssetMultiError = (
  assets: AssetObjectValue[] | undefined,
  isRequired?: boolean,
) => {
  const errors = assets?.map((asset) => {
    if (asset?.type && asset.type === "native") {
      return false;
    }

    const invalid = Object.entries({
      code: getAssetCodeError(asset?.code || "", asset?.type, isRequired),
      issuer: getPublicKeyError(asset?.issuer || "", isRequired),
    }).reduce((res, cur) => {
      const [key, value] = cur;

      if (value) {
        return { ...res, [key]: value };
      }

      return res;
    }, {});

    return isEmptyObject(invalid) ? false : invalid;
  });

  const sanitized = sanitizeArray(errors || []);

  return sanitized.length === 0 ? false : errors;
};
