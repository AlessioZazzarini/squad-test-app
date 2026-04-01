---
name: latest-model-selector
description: "Query live model databases to find the latest and best AI models. Use before any task that references a specific model (debates, API calls, config). Never rely on memorized model names."
user_invocable: true
---

# /latest-models -- Always Use the Latest AI Models

Never hardcode or guess model names. Query live data first.

## Invocation

```
/latest-models                     -> show latest models across all providers
/latest-models anthropic           -> latest Anthropic models only
/latest-models openai              -> latest OpenAI models only
/latest-models google              -> latest Google models only
/latest-models best-for coding     -> best model for a specific task
/latest-models cheapest            -> cheapest capable chat models
```

## Instructions

When invoked (directly or by another skill), follow these steps.

### Step 1: Query Live Sources

Run these queries in parallel to get fresh data:

#### Source A: LiteLLM Database (comprehensive pricing + capabilities)

```bash
curl -sf "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json" -o /tmp/litellm-models.json
```

#### Source B: OpenRouter API (newest models, sorted by release date)

```bash
curl -sf "https://openrouter.ai/api/v1/models" -o /tmp/openrouter-models.json
```

### Step 2: Parse Based on Query Type

#### Default / Provider Filter

Show the latest models for the requested provider(s). Use jq to filter and sort:

```bash
# Latest Anthropic models from LiteLLM
cat /tmp/litellm-models.json | jq 'to_entries[] | select(.key | test("^claude|^anthropic/claude")) | {name: .key, input_mtok: (.value.input_cost_per_token * 1000000), output_mtok: (.value.output_cost_per_token * 1000000), context: .value.max_input_tokens, max_output: .value.max_output_tokens}' 2>/dev/null

# Latest OpenAI models from LiteLLM
cat /tmp/litellm-models.json | jq 'to_entries[] | select(.key | test("^gpt-|^o[0-9]|^openai/")) | {name: .key, input_mtok: (.value.input_cost_per_token * 1000000), output_mtok: (.value.output_cost_per_token * 1000000), context: .value.max_input_tokens, max_output: .value.max_output_tokens}' 2>/dev/null

# Latest Google models from LiteLLM
cat /tmp/litellm-models.json | jq 'to_entries[] | select(.key | test("^gemini|^google/")) | {name: .key, input_mtok: (.value.input_cost_per_token * 1000000), output_mtok: (.value.output_cost_per_token * 1000000), context: .value.max_input_tokens, max_output: .value.max_output_tokens}' 2>/dev/null

# 10 newest models on OpenRouter (any provider)
cat /tmp/openrouter-models.json | jq -r '.data | sort_by(-.created) | .[:10][] | "\(.id) | ctx:\(.context_length) | $\((.pricing.prompt|tonumber)*1e6*100|round/100)/$\((.pricing.completion|tonumber)*1e6*100|round/100) per MTok | \(.created | todate)"' 2>/dev/null
```

#### `best-for <task>`

Cross-reference model capabilities in LiteLLM with the task:
- **coding/reasoning**: Look for models with `supports_reasoning: true` or known reasoning models (o-series, claude with extended thinking)
- **vision**: Filter `supports_vision: true`
- **long context**: Sort by `max_input_tokens` descending
- **cheap**: Sort by `input_cost_per_token + output_cost_per_token` ascending

#### `cheapest`

```bash
cat /tmp/litellm-models.json | jq 'to_entries | map(select(.value.mode == "chat" and .value.input_cost_per_token > 0)) | sort_by(.value.input_cost_per_token + .value.output_cost_per_token) | .[:15][] | {name: .key, input_mtok: (.value.input_cost_per_token * 1000000), output_mtok: (.value.output_cost_per_token * 1000000), context: .value.max_input_tokens}'
```

### Step 3: Present Results

Display a clean table:

```
## Latest [Provider] Models (queried live)

| Model ID | Input $/MTok | Output $/MTok | Context | Max Output |
|----------|-------------|---------------|---------|------------|
| ...      | ...         | ...           | ...     | ...        |

Source: LiteLLM database + OpenRouter API (queried just now)
```

Highlight:
- The **latest generation** in each family (e.g., if both claude-sonnet-4-5 and claude-sonnet-4-6 exist, mark 4-6 as latest)
- Any model released in the last 30 days (based on OpenRouter `created` timestamp)

### Step 4: Recommend

Based on the query, give a concrete recommendation:

```
Recommendation: Use `[model-id]` -- [one-line reason]
```

## Usage by Other Skills

Other skills (like `/debate`) should call this skill's logic before selecting a model. The pattern:

1. Query LiteLLM for the model family needed
2. Pick the latest generation
3. Use that model ID in the command

### Quick Lookup (for internal use by other skills)

When another skill needs "the latest model from provider X", run this minimal check:

```bash
# Latest Claude model for CLI use (non-thinking, chat-capable)
curl -sf "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json" | \
  jq -r 'to_entries[] | select(.key | test("^claude-[a-z]+-[0-9]")) | select(.value.mode == "chat") | .key' | sort -V | tail -5

# Latest GPT/O-series model
curl -sf "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json" | \
  jq -r 'to_entries[] | select(.key | test("^(gpt-|o[0-9])")) | select(.value.mode == "chat") | .key' | sort -V | tail -5

# Latest Gemini model
curl -sf "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json" | \
  jq -r 'to_entries[] | select(.key | test("^gemini-")) | select(.value.mode == "chat") | .key' | sort -V | tail -5
```

## Key Principles

- **If a newer model exists in the same family, use it.** Always latest generation.
- **Refresh before recommending.** Never rely on cached/memorized model names.
- **Cross-reference sources.** LiteLLM has the most models. OpenRouter shows what's newest.
- **Leaderboards for quality:** Check [llm-stats.com](https://llm-stats.com), [lmarena.ai](https://lmarena.ai), or [artificialanalysis.ai](https://artificialanalysis.ai) for "which is best at X" questions.

## Cleanup

```bash
rm -f /tmp/litellm-models.json /tmp/openrouter-models.json
```
