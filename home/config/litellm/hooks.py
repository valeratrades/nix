"""Loaded by both openai.yaml and mixed.yaml (`callbacks:`); litellm puts the config's dir on sys.path."""

from litellm.integrations.custom_logger import CustomLogger

# Claude Code probes a model with a max_tokens=1 request when you `/model <name>`; the OpenAI
# Responses API rejects max_output_tokens below 16, so every switch to an OpenAI group 400s.
OPENAI_MIN_OUTPUT_TOKENS = 16


class ClampMaxTokens(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        if data.get("max_tokens", OPENAI_MIN_OUTPUT_TOKENS) < OPENAI_MIN_OUTPUT_TOKENS:
            data["max_tokens"] = OPENAI_MIN_OUTPUT_TOKENS
        # mixed.yaml `sub-*` (chatgpt/): litellm 1.83.7 lifts only a str system prompt into
        # `instructions`; a block list stays an input item, which the Codex backend 400s on.
        if data.get("model", "").startswith("sub-") and isinstance(data.get("system"), list):
            data["system"] = "\n".join(b["text"] for b in data["system"] if b.get("type") == "text")
        return data


proxy_handler_instance = ClampMaxTokens()
