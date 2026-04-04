"use client";

import {
  IDKitRequestWidget,
  type IDKitResult,
  type IDKitErrorCodes,
  type RpContext,
  orbLegacy,
} from "@worldcoin/idkit";

export default function IDKitWidget({
  appId,
  action,
  rpContext,
  walletAddress,
  open,
  onOpenChange,
  handleVerify,
  onSuccess,
  onError,
}: {
  appId: `app_${string}`;
  action: string;
  rpContext: RpContext;
  walletAddress: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  handleVerify: (result: IDKitResult) => Promise<void>;
  onSuccess: (result: IDKitResult) => void;
  onError: (errorCode: IDKitErrorCodes) => void;
}) {
  return (
    <IDKitRequestWidget
      app_id={appId}
      action={action}
      rp_context={rpContext}
      allow_legacy_proofs={true}
      preset={orbLegacy({ signal: walletAddress })}
      open={open}
      onOpenChange={onOpenChange}
      handleVerify={handleVerify}
      onSuccess={onSuccess}
      onError={onError}
    />
  );
}
