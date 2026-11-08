# Model cost and evidence

Load for long-context routing, alternative models, repricing, or ranking questions.
Reuse this snapshot; refresh only for a model/pricing change or decision-relevant
gap, not each task. Routing authority remains [Plan Loop](../SKILL.md).

## Cost-aware alternatives

Haiku reprices above 100K prompt tokens; Luna/Sol/Terra above 272K.
Above 272K, compare Sonnet's flat rates with Sol's increased rates.
Reduce context to sufficient task evidence, not by discarding needed constraints.
Sonnet is an alternative when task-specific coding evidence beats Sol, not simply
for vendor diversity. Gemini 3.8 Flash and MAI-Code-1.1-Flash need a demonstrated
quality/cost, modality, or latency advantage before becoming coding defaults.
Fallbacks must satisfy the task and the user's explicit model constraints.

## Verified snapshot (2026-11-07)

- [GitHub Copilot pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing):
  base input/output USD per million tokens: Haiku/Luna $0.10/$0.50,
  Terra $1/$5, Sol/Sonnet $2/$10, Opus $4/$20, Gemini $0.75/$3.75,
  MAI $0.20/$1.20. Cache reads/writes and context thresholds affect total cost.
- Artificial Analysis Intelligence Index v5.0.1: [Opus](https://artificialanalysis.ai/models/claude-opus-5-5) 59,
  [Sol](https://artificialanalysis.ai/models/gpt-6-1-sol) and [Sonnet](https://artificialanalysis.ai/models/claude-sonnet-5-5) 55,
  [Terra](https://artificialanalysis.ai/models/gpt-6-1-terra) 51,
  [Haiku](https://artificialanalysis.ai/models/claude-haiku-5-5) 36,
  [Luna](https://artificialanalysis.ai/models/gpt-6-luna) 28,
  [Gemini](https://artificialanalysis.ai/models/gemini-3-8-flash) 31.
  Max-effort deployments except Gemini High; Opus/Sonnet include default fallbacks.
  No comparable MAI score was verified.
- Sol/Sonnet tie at 55, with measured average task costs $1.27/$10.02 at Max.
  This supports Sol's efficiency, not Sonnet inferiority at medium-effort coding.
  [FrontierCode 2.0](https://artificialanalysis.ai/evaluations/frontiercode-2-0)
  ranks Opus Max highest at 46.4%. External harness results are not this app's
  success rates; effort, task mix, token counts, and retries matter.

## Legacy phase reference

For planning/revising via this compatibility path, use the authoritative
[Plan Loop](../SKILL.md) and [Plan](SKILL.md) instructions.