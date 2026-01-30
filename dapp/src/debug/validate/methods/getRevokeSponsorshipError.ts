import { sanitizeObject } from "../../util/sanitizeObject.ts";
import { isEmptyObject } from "../../util/isEmptyObject.ts";
import {
  AnyObject,
  AssetObjectValue,
  AssetPoolShareObjectValue,
  OptionSigner,
  RevokeSponsorshipValue,
} from "../../types/types.ts";

import { getPublicKeyError } from "./getPublicKeyError.ts";
import { getAssetError } from "./getAssetError.ts";
import { getPositiveIntError } from "./getPositiveIntError.ts";
import { getDataNameError } from "./getDataNameError.ts";
import { getClaimableBalanceIdError } from "./getClaimableBalanceIdError.ts";
import { getOptionsSignerError } from "./getOptionsSignerError.ts";

export const getRevokeSponsorshipError = (
  value: RevokeSponsorshipValue | undefined,
) => {
  if (!value || !value.data) {
    return false;
  }

  const cleanResponse = (validation: AnyObject | boolean) => {
    if (typeof validation === "boolean") {
      return validation;
    }

    const valid = sanitizeObject(validation);
    return isEmptyObject(valid) ? false : valid;
  };

  let response: AnyObject | boolean = false;

  switch (value.type) {
    case "account":
      response = {
        account_id: getPublicKeyError(value.data.account_id as string),
      };
      break;
    case "trustline":
      response = {
        account_id: getPublicKeyError(value.data.account_id as string),
        asset: getAssetError(
          value.data.asset as
            | undefined
            | AssetObjectValue
            | AssetPoolShareObjectValue,
        ),
      };
      break;
    case "offer":
      response = {
        seller_id: getPublicKeyError(value.data.seller_id as string),
        offer_id: getPositiveIntError((value.data.offer_id as string) || ""),
      };
      break;
    case "data":
      response = {
        account_id: getPublicKeyError(value.data.account_id as string),
        data_name: getDataNameError((value.data.data_name as string) || ""),
      };
      break;
    case "claimable_balance":
      response = {
        balance_id: getClaimableBalanceIdError(value.data.balance_id as string),
      };
      break;
    case "signer":
      response = {
        account_id: getPublicKeyError(value.data.account_id as string),
        signer: getOptionsSignerError(value.data.signer as OptionSigner),
      };
      break;
    default:
    // Do nothing
  }

  return cleanResponse(response);
};
