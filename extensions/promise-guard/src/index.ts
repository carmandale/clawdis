/**
 * Promise Guard Plugin
 * 
 * Safety net that catches promises in outbound messages.
 * Calls the commitments/scripts/add.sh script to create git-tracked commitments.
 * 
 * Flow: Hook (catches) → Script (executes) → Git (tracks)
 */

import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { ClawdbotPluginApi } from "clawdbot/plugin-sdk";

// Promise patterns to detect
const PROMISE_PATTERNS = [
  /I['']ll\s+(follow up|check on|get back to you|look into|let you know|check back)/i,
  /I\s+will\s+(follow up|check on|get back to you|look into|let you know|check back)/i,
  /Let\s+me\s+(follow up|check on|get back to you|look into|check back)/i,
  /I['']ll\s+have\s+(that|this|it)\s+(ready|done|finished)/i,
  /I['']ll\s+(remind|ping|message|text|notify)\s+(you|dale|him|her)/i,
];

const DEFAULT_FOLLOWUP_HOURS = 24;

function detectPromise(content: string): string | null {
  for (const pattern of PROMISE_PATTERNS) {
    const match = content.match(pattern);
    if (match) {
      return match[0];
    }
  }
  return null;
}

function parseTimeExpressionToISO(content: string): string {
  let offsetMs = DEFAULT_FOLLOWUP_HOURS * 60 * 60 * 1000;
  
  // Check for "in X minutes"
  const minMatch = content.match(/in\s+(\d+)\s*min(ute)?s?/i);
  if (minMatch) {
    offsetMs = parseInt(minMatch[1], 10) * 60 * 1000;
  }
  // Check for "in X hours"
  else if (content.match(/in\s+(\d+)\s*hours?/i)) {
    const hourMatch = content.match(/in\s+(\d+)\s*hours?/i);
    if (hourMatch) offsetMs = parseInt(hourMatch[1], 10) * 60 * 60 * 1000;
  }
  else if (/in\s+an?\s*hour/i.test(content)) offsetMs = 60 * 60 * 1000;
  else if (/in\s+30\s*min/i.test(content)) offsetMs = 30 * 60 * 1000;
  else if (/tomorrow/i.test(content)) offsetMs = 24 * 60 * 60 * 1000;
  else if (/later\s+(today|tonight)/i.test(content)) offsetMs = 4 * 60 * 60 * 1000;
  else if (/this\s+(afternoon|evening)/i.test(content)) offsetMs = 4 * 60 * 60 * 1000;
  else if (/next\s+week/i.test(content)) offsetMs = 7 * 24 * 60 * 60 * 1000;

  const dueDate = new Date(Date.now() + offsetMs);
  return dueDate.toISOString();
}

function findCommitmentsScript(): string | null {
  // Look for the commitments script in known locations
  const candidates = [
    join(homedir(), "chipbot", "commitments", "scripts", "add.sh"),
    join(homedir(), "clawd", "commitments", "scripts", "add.sh"),
    join(process.cwd(), "commitments", "scripts", "add.sh"),
  ];
  
  for (const path of candidates) {
    if (existsSync(path)) {
      return path;
    }
  }
  return null;
}

function escapeShellArg(arg: string): string {
  return `'${arg.replace(/'/g, "'\\''")}'`;
}

export function register(api: ClawdbotPluginApi): void {
  api.logger.info("Promise Guard plugin loaded");
  
  const scriptPath = findCommitmentsScript();
  if (!scriptPath) {
    api.logger.warn("Commitments script not found - promise detection disabled");
    api.logger.warn("Expected at: ~/chipbot/commitments/scripts/add.sh");
    return;
  }
  
  api.logger.info(`Using commitments script: ${scriptPath}`);

  // Hook into message_sending to detect promises
  api.on("message_sending", async (event, ctx) => {
    const { content } = event;
    const { channel } = ctx;
    const to = event.to;
    
    if (!content || typeof content !== "string") {
      return;
    }
    
    const promiseMatch = detectPromise(content);
    if (!promiseMatch) {
      return;
    }
    
    api.logger.info(`Promise detected: "${promiseMatch}"`);
    
    // Extract the promise sentence
    const sentences = content.split(/[.!?]+/);
    const promiseSentence = sentences.find(s => 
      PROMISE_PATTERNS.some(p => p.test(s))
    ) || promiseMatch;
    
    // Parse when to follow up
    const dueAt = parseTimeExpressionToISO(content);
    
    // Build script command
    const cmd = [
      scriptPath,
      "--who", escapeShellArg(to || "unknown"),
      "--channel", escapeShellArg(channel || "unknown"),
      "--what", escapeShellArg(promiseSentence.trim()),
      "--due", escapeShellArg(dueAt),
      "--context", escapeShellArg(`Auto-detected by promise-guard hook. Original: "${content.slice(0, 200)}..."`),
    ].join(" ");
    
    try {
      const output = execSync(cmd, { 
        encoding: "utf-8",
        timeout: 10000,
        stdio: ["pipe", "pipe", "pipe"],
      });
      api.logger.info(`Commitment created via script: ${output.split("\n").pop()}`);
    } catch (err) {
      api.logger.error(`Failed to create commitment: ${String(err)}`);
    }
    
    // Let the message through unchanged - commitment is tracked
    return;
  });
}
