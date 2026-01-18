import { loadConfig } from "../config/config.js";
import { mediaKindFromMime } from "../media/constants.js";
import { saveMediaBuffer } from "../media/store.js";
import { loadWebMedia } from "../web/media.js";
import { resolveIMessageAccount } from "./accounts.js";
import { createIMessageRpcClient, type IMessageRpcClient } from "./client.js";
import { formatIMessageChatTarget, type IMessageService, parseIMessageTarget } from "./targets.js";

export type IMessageSendOpts = {
  cliPath?: string;
  dbPath?: string;
  service?: IMessageService;
  region?: string;
  accountId?: string;
  mediaUrl?: string;
  maxBytes?: number;
  timeoutMs?: number;
  chatId?: number;
  client?: IMessageRpcClient;
};

export type IMessageSendResult = {
  messageId: string;
};

async function resolveAttachment(
  mediaUrl: string,
  maxBytes: number,
): Promise<{ path: string; contentType?: string }> {
  const media = await loadWebMedia(mediaUrl, maxBytes);
  const saved = await saveMediaBuffer(
    media.buffer,
    media.contentType ?? undefined,
    "outbound",
    maxBytes,
  );
  return { path: saved.path, contentType: saved.contentType };
}

export async function sendMessageIMessage(
  to: string,
  text: string,
  opts: IMessageSendOpts = {},
): Promise<IMessageSendResult> {
  const cfg = loadConfig();
  const account = resolveIMessageAccount({
    cfg,
    accountId: opts.accountId,
  });

  // Enforce outbound allowlist if configured
  const allowSendTo = account.config.allowSendTo;
  if (allowSendTo && allowSendTo.length > 0) {
    // Block chatId-based sends when allowSendTo is configured (can't verify recipient)
    if (opts.chatId) {
      throw new Error(
        `iMessage send blocked: chatId-based sends not allowed when allowSendTo is configured. ` +
          `Use explicit recipient address instead.`,
      );
    }
    const normalizedTo = to.replace(/[\s\-()]/g, "").toLowerCase();
    const normalizedAllowList = allowSendTo.map((entry) =>
      entry.replace(/[\s\-()]/g, "").toLowerCase(),
    );
    const isAllowed = normalizedAllowList.some(
      (allowed) => normalizedTo.includes(allowed) || allowed.includes(normalizedTo),
    );
    if (!isAllowed) {
      throw new Error(
        `iMessage send blocked: "${to}" is not in allowSendTo list. ` +
          `Only these recipients are allowed: ${allowSendTo.join(", ")}`,
      );
    }
  }

  const cliPath = opts.cliPath?.trim() || account.config.cliPath?.trim() || "imsg";
  const dbPath = opts.dbPath?.trim() || account.config.dbPath?.trim();
  const target = parseIMessageTarget(opts.chatId ? formatIMessageChatTarget(opts.chatId) : to);

  // Apply message prefix if configured (e.g., "🐿️ Chip:")
  const messagePrefix = account.config.messagePrefix;
  const prefixedText = messagePrefix ? `${messagePrefix} ${text}` : text;
  const service =
    opts.service ??
    (target.kind === "handle" ? target.service : undefined) ??
    (account.config.service as IMessageService | undefined);
  const region = opts.region?.trim() || account.config.region?.trim() || "US";
  const maxBytes =
    typeof opts.maxBytes === "number"
      ? opts.maxBytes
      : typeof account.config.mediaMaxMb === "number"
        ? account.config.mediaMaxMb * 1024 * 1024
        : 16 * 1024 * 1024;
  let message = prefixedText ?? "";
  let filePath: string | undefined;

  if (opts.mediaUrl?.trim()) {
    const resolved = await resolveAttachment(opts.mediaUrl.trim(), maxBytes);
    filePath = resolved.path;
    if (!message.trim()) {
      const kind = mediaKindFromMime(resolved.contentType ?? undefined);
      if (kind) message = kind === "image" ? "<media:image>" : `<media:${kind}>`;
    }
  }

  if (!message.trim() && !filePath) {
    throw new Error("iMessage send requires text or media");
  }

  const params: Record<string, unknown> = {
    text: message,
    service: (service || "auto") as IMessageService,
    region,
  };
  if (filePath) params.file = filePath;

  if (target.kind === "chat_id") {
    params.chat_id = target.chatId;
  } else if (target.kind === "chat_guid") {
    params.chat_guid = target.chatGuid;
  } else if (target.kind === "chat_identifier") {
    params.chat_identifier = target.chatIdentifier;
  } else {
    params.to = target.to;
  }

  const client = opts.client ?? (await createIMessageRpcClient({ cliPath, dbPath }));
  const shouldClose = !opts.client;
  try {
    const result = await client.request<{ ok?: boolean }>("send", params, {
      timeoutMs: opts.timeoutMs,
    });
    return {
      messageId: result?.ok ? "ok" : "unknown",
    };
  } finally {
    if (shouldClose) {
      await client.stop();
    }
  }
}
