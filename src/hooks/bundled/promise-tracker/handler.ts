/**
 * Promise Tracker Hook
 * 
 * Injects open promises into agent context at bootstrap.
 * Works with promise-guard plugin to ensure follow-through on commitments.
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { isAgentBootstrapEvent, type HookHandler } from "../../hooks.js";

type PromiseEntry = {
  id: string;
  createdAt: string;
  who: string;
  channel: string;
  what: string;
  originalText: string;
  context?: string;
  dueAt: string;
  status: "open" | "fulfilled" | "expired";
  sessionKey?: string;
};

const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

function getLedgerPath(): string {
  return join(homedir(), ".clawdbot", "promises.jsonl");
}

function readOpenPromises(): PromiseEntry[] {
  const ledgerPath = getLedgerPath();
  
  if (!existsSync(ledgerPath)) {
    return [];
  }
  
  try {
    const content = readFileSync(ledgerPath, "utf-8");
    const lines = content.trim().split("\n").filter(Boolean);
    const now = Date.now();
    
    const promises: PromiseEntry[] = [];
    
    for (const line of lines) {
      try {
        const entry = JSON.parse(line) as PromiseEntry;
        
        // Skip non-open promises
        if (entry.status !== "open") continue;
        
        // Skip promises older than MAX_AGE_MS
        const createdAt = new Date(entry.createdAt).getTime();
        if (now - createdAt > MAX_AGE_MS) continue;
        
        promises.push(entry);
      } catch {
        // Skip malformed lines
        continue;
      }
    }
    
    return promises;
  } catch (err) {
    console.error("[promise-tracker] Failed to read ledger:", err);
    return [];
  }
}

function formatPromisesForContext(promises: PromiseEntry[]): string {
  if (promises.length === 0) {
    return "";
  }
  
  const now = new Date();
  const lines: string[] = [
    "",
    "---",
    "## ⚠️ OPEN COMMITMENTS",
    "",
    "You have made the following promises that are still open:",
    "",
  ];
  
  for (let i = 0; i < promises.length; i++) {
    const p = promises[i];
    const dueDate = new Date(p.dueAt);
    const isOverdue = dueDate < now;
    const overdueMarker = isOverdue ? " **[OVERDUE]**" : "";
    
    lines.push(`### ${i + 1}. ${p.id}${overdueMarker}`);
    lines.push(`- **To:** ${p.who} (${p.channel})`);
    lines.push(`- **Due:** ${p.dueAt}`);
    lines.push(`- **What:** "${p.what}"`);
    lines.push("");
  }
  
  lines.push("*Address these commitments or mark them as fulfilled by updating ~/.clawdbot/promises.jsonl*");
  lines.push("---");
  lines.push("");
  
  return lines.join("\n");
}

const promiseTrackerHook: HookHandler = async (event) => {
  if (!isAgentBootstrapEvent(event)) return;
  
  const promises = readOpenPromises();
  
  if (promises.length === 0) {
    return;
  }
  
  console.log(`[promise-tracker] Found ${promises.length} open promise(s)`);
  
  const promiseContext = formatPromisesForContext(promises);
  const context = event.context;
  
  // Find MEMORY.md in bootstrap files and append to it
  const memoryFile = context.bootstrapFiles.find(
    f => f.path.endsWith("MEMORY.md") || f.path.endsWith("memory.md")
  );
  
  if (memoryFile) {
    memoryFile.content = (memoryFile.content || "") + promiseContext;
    console.log(`[promise-tracker] Injected ${promises.length} promise(s) into MEMORY.md context`);
  } else {
    // Look for any file we can append to, or just log
    const anyFile = context.bootstrapFiles.find(f => f.content);
    if (anyFile) {
      anyFile.content = (anyFile.content || "") + promiseContext;
      console.log(`[promise-tracker] Injected ${promises.length} promise(s) into ${anyFile.name} context`);
    } else {
      console.log(`[promise-tracker] No writable bootstrap file found, ${promises.length} promise(s) not injected`);
    }
  }
};

export default promiseTrackerHook;
