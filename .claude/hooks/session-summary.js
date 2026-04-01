#!/usr/bin/env node
/**
 * AgentSquad Session Summary Hook — Stop (debounced)
 *
 * Parses the Claude Code transcript JSONL and writes one summary
 * object per session to ~/.claude/logs/session-summaries.jsonl.
 *
 * Cost optimization: Stop fires after every assistant turn, but we
 * only re-parse the transcript when:
 *   1. At least 30s have passed since last parse, OR
 *   2. The transcript file has grown since last parse
 * State is tracked in ~/.claude/logs/sessions/<session_id>.meta.json
 *
 * Metrics tracked (15 + 1 bonus):
 *  1. wall_time_s          — seconds from first to last message
 *  2. active_time_s        — estimated assistant-active time
 *  3. turns                — number of user messages (conversation turns)
 *  4. exit_reason          — heuristic: "user_exit" | "task_complete" | "unknown"
 *  5. tool_calls_ok        — tool calls that succeeded
 *  6. tool_calls_err       — tool calls that errored
 *  7. files_read           — unique files read via Read tool
 *  8. files_edited         — unique files edited via Edit tool
 *  9. files_created        — unique files created via Write tool
 * 10. agents_used          — array of {type, description} for Agent tool calls
 * 11. skills_used          — array of skill names invoked
 * 12. git_diff_summary     — {insertions, deletions, files_changed}
 * 13. model_usage          — {model, requests, input_tokens, output_tokens, ...}
 * 14. cache_hit_rate       — ratio of cache_read to total input tokens
 * 15. estimated_cost_usd   — estimated session cost based on token pricing
 * 16. lines_written        — net lines of code added via Edit/Write
 */

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const DEBOUNCE_S = 30;
const LOGS_DIR = path.join(process.env.HOME, ".claude", "logs");
const SESSIONS_DIR = path.join(LOGS_DIR, "sessions");
const SUMMARIES_FILE = path.join(LOGS_DIR, "session-summaries.jsonl");

// ── Pricing (per 1M tokens, USD) ──────────────────────────────────
const PRICING = {
  "claude-opus-4-6": { input: 15, output: 75, cache_read: 1.5, cache_write: 18.75 },
  "claude-sonnet-4-6": { input: 3, output: 15, cache_read: 0.3, cache_write: 3.75 },
  "claude-haiku-4-5": { input: 0.8, output: 4, cache_read: 0.08, cache_write: 1 },
  default: { input: 15, output: 75, cache_read: 1.5, cache_write: 18.75 },
};

function getPricing(model) {
  if (!model) return PRICING.default;
  for (const key of Object.keys(PRICING)) {
    if (key !== "default" && model.startsWith(key.replace(/-\d+$/, ""))) {
      return PRICING[key];
    }
  }
  return PRICING[model] || PRICING.default;
}

// ── Debounce check ────────────────────────────────────────────────
function shouldSkip(sessionId, transcriptPath) {
  const metaFile = path.join(SESSIONS_DIR, `${sessionId}.meta.json`);
  if (!fs.existsSync(metaFile)) return false;

  try {
    const meta = JSON.parse(fs.readFileSync(metaFile, "utf8"));
    const now = Date.now();
    const elapsed = (now - meta.last_parse_ms) / 1000;
    const currentSize = fs.statSync(transcriptPath).size;

    // Parse if: enough time passed OR transcript grew
    if (elapsed >= DEBOUNCE_S) return false;
    if (currentSize !== meta.transcript_size) return false;

    // Neither condition met — skip
    return true;
  } catch {
    return false;
  }
}

function saveMeta(sessionId, transcriptSize) {
  if (!fs.existsSync(SESSIONS_DIR)) {
    fs.mkdirSync(SESSIONS_DIR, { recursive: true });
  }
  fs.writeFileSync(
    path.join(SESSIONS_DIR, `${sessionId}.meta.json`),
    JSON.stringify({ last_parse_ms: Date.now(), transcript_size: transcriptSize })
  );
}

// ── Read hook input from stdin ────────────────────────────────────
function readStdin() {
  try {
    return JSON.parse(fs.readFileSync("/dev/stdin", "utf8"));
  } catch {
    return {};
  }
}

// ── Parse transcript ──────────────────────────────────────────────
function parseTranscript(transcriptPath) {
  const raw = fs.readFileSync(transcriptPath, "utf8").trim();
  if (!raw) return null;

  const lines = raw.split("\n");
  const parsed = [];
  for (const l of lines) {
    try { parsed.push(JSON.parse(l)); } catch { /* skip malformed */ }
  }

  const userMsgs = [];
  const assistantMsgs = [];
  const allTimestamped = [];

  for (const entry of parsed) {
    if (entry.timestamp) allTimestamped.push(entry);
    if (entry.type === "user") userMsgs.push(entry);
    else if (entry.type === "assistant") assistantMsgs.push(entry);
  }

  if (allTimestamped.length === 0) return null;

  // 1. Wall time
  let startTime = Infinity, endTime = -Infinity;
  for (const e of allTimestamped) {
    const t = new Date(e.timestamp).getTime();
    if (t < startTime) startTime = t;
    if (t > endTime) endTime = t;
  }
  const wallTimeS = Math.round((endTime - startTime) / 1000);

  // 2. Active time — sum gaps where assistant/progress messages are consecutive
  let activeTimeS = 0;
  for (let i = 1; i < allTimestamped.length; i++) {
    const type = allTimestamped[i].type;
    if (type === "assistant" || type === "progress") {
      const gap = new Date(allTimestamped[i].timestamp).getTime() -
                  new Date(allTimestamped[i - 1].timestamp).getTime();
      if (gap < 120_000) activeTimeS += gap / 1000;
    }
  }
  activeTimeS = Math.round(activeTimeS);

  // 3. Turns
  let turns = 0;
  for (const m of userMsgs) {
    const c = m.message?.content;
    if (typeof c === "string") { turns++; continue; }
    if (Array.isArray(c) && c.some((b) => b.type === "text")) turns++;
  }

  // 4. Exit reason
  let exitReason = "unknown";
  if (userMsgs.length > 0) {
    const last = userMsgs[userMsgs.length - 1];
    const c = last.message?.content;
    if (typeof c === "string") {
      const lc = c.toLowerCase();
      if (/\b(bye|thanks|done|that's it|exit|quit)\b/.test(lc)) exitReason = "user_exit";
    }
  }
  if (exitReason === "unknown" && assistantMsgs.length > 0) {
    const last = assistantMsgs[assistantMsgs.length - 1];
    const content = last.message?.content || [];
    if (Array.isArray(content) && !content.some((b) => b.type === "tool_use")) {
      exitReason = "task_complete";
    }
  }

  // 5-11. Tool calls, files, agents, skills
  const toolUses = [];
  for (const msg of assistantMsgs) {
    const content = msg.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type === "tool_use") {
        toolUses.push({ id: block.id, name: block.name, input: block.input });
      }
    }
  }

  const toolResults = new Map();
  for (const msg of userMsgs) {
    const content = msg.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type === "tool_result") {
        toolResults.set(block.tool_use_id, block.is_error === true);
      }
    }
  }

  let toolCallsOk = 0, toolCallsErr = 0;
  const filesRead = new Set();
  const filesEdited = new Set();
  const filesCreated = new Set();
  const agentsUsed = [];
  const skillSet = new Set();
  let linesWritten = 0;

  for (const tu of toolUses) {
    // OK/ERR
    if (toolResults.get(tu.id)) toolCallsErr++;
    else toolCallsOk++;

    // Files
    const fp = tu.input?.file_path;
    switch (tu.name) {
      case "Read":  if (fp) filesRead.add(fp); break;
      case "Edit":  if (fp) filesEdited.add(fp); break;
      case "Write": if (fp) filesCreated.add(fp); break;
      case "Agent":
        agentsUsed.push({
          type: tu.input?.subagent_type || "general-purpose",
          description: tu.input?.description || "",
        });
        break;
      case "Skill":
        skillSet.add(tu.input?.skill || "unknown");
        break;
    }

    // Lines written
    if (tu.name === "Write" && tu.input?.content) {
      linesWritten += tu.input.content.split("\n").length;
    } else if (tu.name === "Edit" && tu.input?.new_string) {
      const added = tu.input.new_string.split("\n").length;
      const removed = (tu.input.old_string || "").split("\n").length;
      linesWritten += Math.max(0, added - removed);
    }
  }

  // 12. Git diff summary
  let gitDiffSummary = { insertions: 0, deletions: 0, files_changed: 0 };
  try {
    const cwd = parsed.find((l) => l.cwd)?.cwd || process.cwd();
    const diffStat = execSync("git diff --stat HEAD 2>/dev/null || true", {
      cwd, encoding: "utf8", timeout: 5000,
    });
    const summaryLine = diffStat.trim().split("\n").pop() || "";
    const fm = summaryLine.match(/(\d+)\s+files?\s+changed/);
    const im = summaryLine.match(/(\d+)\s+insertions?\(\+\)/);
    const dm = summaryLine.match(/(\d+)\s+deletions?\(-\)/);
    gitDiffSummary = {
      insertions: im ? parseInt(im[1]) : 0,
      deletions: dm ? parseInt(dm[1]) : 0,
      files_changed: fm ? parseInt(fm[1]) : 0,
    };
  } catch { /* ignore */ }

  // 13-15. Model usage, cache hit rate, cost
  let totalIn = 0, totalOut = 0, totalCacheRead = 0, totalCacheWrite = 0;
  let requests = 0, primaryModel = null;

  for (const msg of assistantMsgs) {
    const u = msg.message?.usage;
    if (!u) continue;
    requests++;
    totalIn += u.input_tokens || 0;
    totalOut += u.output_tokens || 0;
    totalCacheRead += u.cache_read_input_tokens || 0;
    totalCacheWrite += u.cache_creation_input_tokens || 0;
    if (!primaryModel && msg.message?.model) primaryModel = msg.message.model;
  }

  const totalInput = totalIn + totalCacheRead + totalCacheWrite;
  const cacheHitRate = totalInput > 0
    ? Math.round((totalCacheRead / totalInput) * 1000) / 1000
    : 0;

  const p = getPricing(primaryModel);
  const estimatedCostUsd = Math.round(
    ((totalIn * p.input + totalOut * p.output +
      totalCacheRead * p.cache_read + totalCacheWrite * p.cache_write) / 1_000_000) * 10000
  ) / 10000;

  return {
    wall_time_s: wallTimeS,
    active_time_s: activeTimeS,
    turns,
    exit_reason: exitReason,
    tool_calls_ok: toolCallsOk,
    tool_calls_err: toolCallsErr,
    files_read: [...filesRead],
    files_edited: [...filesEdited],
    files_created: [...filesCreated],
    agents_used: agentsUsed,
    skills_used: [...skillSet],
    git_diff_summary: gitDiffSummary,
    model_usage: {
      model: primaryModel || "unknown",
      requests,
      input_tokens: totalIn,
      output_tokens: totalOut,
      cache_read_tokens: totalCacheRead,
      cache_write_tokens: totalCacheWrite,
    },
    cache_hit_rate: cacheHitRate,
    estimated_cost_usd: estimatedCostUsd,
    lines_written: linesWritten,
  };
}

// ── Write summary (upsert by session_id) ──────────────────────────
function writeSummary(summary) {
  if (!fs.existsSync(LOGS_DIR)) fs.mkdirSync(LOGS_DIR, { recursive: true });

  const newLine = JSON.stringify(summary);

  if (fs.existsSync(SUMMARIES_FILE)) {
    const existing = fs.readFileSync(SUMMARIES_FILE, "utf8").trim().split("\n").filter(Boolean);
    const filtered = existing.filter((line) => {
      try { return JSON.parse(line).session_id !== summary.session_id; }
      catch { return true; }
    });
    filtered.push(newLine);
    fs.writeFileSync(SUMMARIES_FILE, filtered.join("\n") + "\n");
  } else {
    fs.writeFileSync(SUMMARIES_FILE, newLine + "\n");
  }
}

// ── Main ──────────────────────────────────────────────────────────
function main() {
  const hookInput = readStdin();
  const transcriptPath = hookInput.transcript_path;
  const sessionId = hookInput.session_id;
  const cwd = hookInput.cwd || process.cwd();

  if (!transcriptPath || !sessionId || !fs.existsSync(transcriptPath)) {
    process.exit(0);
  }

  // Debounce: skip if transcript hasn't changed and <30s since last parse
  if (shouldSkip(sessionId, transcriptPath)) {
    process.exit(0);
  }

  const metrics = parseTranscript(transcriptPath);
  if (!metrics) process.exit(0);

  const summary = {
    session_id: sessionId,
    timestamp: new Date().toISOString(),
    cwd,
    project: path.basename(cwd),
    ...metrics,
  };

  writeSummary(summary);
  saveMeta(sessionId, fs.statSync(transcriptPath).size);
}

main();
