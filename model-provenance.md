# Model provenance

## Open-weight models

The seven open-weight models were served with Ollama 0.30.9 and pulled from the Ollama library on 16 June 2026. All runs used greedy decoding (temperature 0, top-p 0, top-k 1). The build IDs are the identifiers that `ollama list` shows.

| Model | Build ID | Size | Full digest |
|---|---|---|---|
| qwen3.5:122b | 8b9d11d807c5 | 81 GB | sha256:8b9d11d807c57feb1e2ecb0d6cbf40334c37dcc3523bed5540af4f927f112a37 |
| qwen3.6:35b | 07d35212591f | 24 GB | only the short ID was recorded |
| qwen3-coder:30b | 06c1097efce0 | 19 GB | sha256:06c1097efce0431c2045fe7b2e5108366e43bee1b4603a7aded8f21689e90bca |
| mistral-small3.2:24b | 5a408ab55df5 | 15 GB | sha256:5a408ab55df5c1b5cf46533c368813b30bf9e4d8fc39263bf2a3338cfa3b895b |
| codestral:22b | 0898a8b286d5 | 13 GB | sha256:0898a8b286d56d8105587049fec69634fce83c957230fc13f0acfe03b7b11909 |
| gemma4:12b | 4eb23ef187e2 | 7.6 GB | sha256:4eb23ef187e2c5462566d6a1d3bbbc2f1346d0b4327cbb66d58fffbcc9b2b05c |
| codegemma:7b | 0c96700aaada | 5.0 GB | sha256:0c96700aaada572ce9bb6999d1fda9b53e9e6cef5d74fda1e066a1ba811b93f3 |

The tags `qwen3.6:35b` and `gemma4:12b` were republished in the Ollama library after the runs, on 1 and 30 September 2026. Pulling these two models by tag now returns other builds than the ones listed here.

P1 ran with a context window of 4,096 tokens and P2 with 16,384 tokens. Prompts that did not fit were repeated with a larger window. 

## Hosted models

| Column | Provider | API model ID | Reasoning | Output limit | Run date P1 | Run date P2 |
|---|---|---|---|---|---|---|
| `gpt-5.6-luna-low` | OpenAI | `gpt-5.6-luna` | `reasoning_effort: low` | 4,000 tokens, including reasoning | 2026-09-30 | 2026-09-28 |
| `gpt-5.6-luna-high` | OpenAI | `gpt-5.6-luna` | `reasoning_effort: high` | 16,000 tokens, including reasoning | 2026-09-30 | 2026-09-28 |
| `claude-sonnet-5-5` | Anthropic | `claude-sonnet-5-5`, a pinned snapshot of Claude Sonnet 5.5 | no extended thinking, effort at the API default | 1,024 tokens | 2026-10-01 | 2026-09-30 |

All hosted runs used the same prompts as the open-weight runs, went through the providers' batch APIs with the default sampling settings, and requested structured output in the JSON schema `{"bugfix": boolean}`. Prompts longer than 350,000 characters, 3 for P1 and 40 for P2, were shortened by removing the middle of the diff, so the instructions stayed complete. Every commit received a verdict.
