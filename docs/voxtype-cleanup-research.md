# VoxType dictation cleanup research (27 Oct 2026)

## Bottom line

Post-processing in VoxType is an external command on the batch transcription path, so it can do cleanup, self-corrections, or list formatting without changing ASR. For this user's 0.46 s stop-to-paste baseline, every synchronous LLM call adds its own inference/transport time; there is no trustworthy primary-source benchmark showing that local cleanup would keep the total near 0.46 s on this RTX 4070 Ti SUPER/Ryzen 5700X. VoxType's own v1.1.1 example recommends a small 1–3B local instruct model for lower latency, but reports no timing or measured success rate. The low-risk research conclusion is: try deterministic replacements/formatting first; if a language model is worth an experiment, use a small local non-reasoning model, keep it resident/warm if practical, and measure the added release-to-paste delay and edit burden yourself.

No dictation was sent to a cloud service as part of this research. Cloud cleanup is technically supported by official examples, but is not appropriate under the stated no-cloud-dictation constraint.

## What VoxType supports in the installed version

- The v1.1.1 configuration supports `[output.post_process] command` and a timeout; the child command receives recognized text on stdin and returns transformed text on stdout. See the [v1.1.1 config reference](https://github.com/peteonrails/voxtype/blob/v1.1.1/docs/CONFIGURATION.md) and [tagged Ollama example](https://github.com/peteonrails/voxtype/blob/v1.1.1/examples/ollama-cleanup.sh).
- That example calls the local Ollama HTTP API with `llama3.2:1b`, `stream: false`, and a prompt to remove fillers and fix grammar/punctuation. Its comments recommend small 1–3B instruct/chat models (not reasoning models) for lower latency. This is a maintainer-provided recipe, **not a user benchmark**: it gives no measured response time, hardware, warm/cold state, or cleanup accuracy.
- The equivalent [OpenAI example](https://github.com/peteonrails/voxtype/blob/v1.1.1/examples/openai-cleanup.sh) uses `gpt-4o-mini`, caps output at 1,000 tokens, gives curl an 8-second maximum, and falls back to original text if the response is empty or the API key is missing. The [Gemini example](https://github.com/peteonrails/voxtype/blob/v1.1.1/examples/gemini-cleanup.sh) similarly uses `gemini-2.0-flash`, an 8-second curl maximum, and original-text fallback. These demonstrate alternatives, not comparative latency evidence.
- The maintainer's [v1.1.1 release notes](https://github.com/peteonrails/voxtype/releases/tag/v1.1.1) say post-processing is opt-in and document a prior TUI bug that saved its command under an ignored top-level section; the correct section is `[output.post_process]`. Use the version-matched config reference, not newer docs blindly.
- Post-processing applies to batch paths, not live streaming. One firsthand reporter in [issue #813](https://github.com/peteonrails/voxtype/issues/813) says Soniox streaming text was ready roughly 0.1–0.2 s after stop, but cleaning required a custom file/script/paste workflow; disabling streaming instead made their wait grow about 0.6× speech duration in their tests. This is one user's report, not a general performance guarantee. It also does not describe local LLM inference.

## User reports vs. evidence

The public firsthand VoxType material located for this question is sparse on **LLM cleanup** specifically. Issue #813 is a concrete user workflow and latency anecdote, but has no LLM model or cleanup timing. Issue [#231](https://github.com/peteonrails/voxtype/issues/231) proposes a “meeting notes” intent that would send text to GPT for action-item bullets; it is a feature request, not evidence the reporter had implemented or tested it. The release-tagged examples are the strongest direct evidence for available local/cloud patterns, but are maintainer-authored examples. I found no credible measured local cleanup latency or success-rate report on comparable hardware; do not infer one from ASR benchmark numbers or claims about “fast” models.

The LLM can also rewrite correct recognition into incorrect text. Formatting tasks (e.g. “format the following dictated items as a Markdown list; preserve wording and order”) are narrower than free-form polishing and easier to verify. Treat proper-noun “self-corrections” cautiously: a cleanup model only sees text, not audio, so it cannot reliably recover a word that ASR changed into a plausible alternative unless the correction is explicit/contextual. The repository examples prompt for cleanup, but publish no evaluation of hallucinations, formatting fidelity, or before/after corrections.

## Local model and warm/cold tradeoffs

- **Candidate class, not a guaranteed winner:** a compact 1B–3B instruct/chat model. The official Ollama script specifically names `llama3.2:1b`; its guidance is qualitative. It does not provide a tested quantization, token rate, memory number, or total latency on a 5700X/4070 Ti SUPER.
- **Warm vs cold:** Ollama is an always-running local service in the example (`ollama serve` requirement), but the example does not set keep-alive or show model residency. A resident model avoids model-load-on-first-request costs in principle; if memory pressure makes it unload, first-call latency can differ. This is a general serving consideration, not a measured VoxType result. Do not assume the `[whisper] on_demand_loading` setting controls Ollama—it only controls the ASR model.
- The supplied machine has ample system RAM and GPU VRAM for experimenting with a small model, but simultaneous Whisper/LLM GPU use can contend for GPU resources. CPU inference may avoid that contention while taking longer. Which is faster is unmeasured here. Benchmark both warm repeated runs and a first/cold request only if the cold case matters to actual use.
- With short speech, process launch, request setup, prompt prefill, and generation may dominate. Keep the prompt concise and cap output to the input's likely size. A format-only task may be better served by a deterministic script; an LLM need not run for every utterance.

## Cloud alternatives and privacy

VoxType v1.1.1 ships example scripts for OpenAI Chat Completions and Gemini generateContent. Both send the **recognized transcript text** (and optional prior transcript context) to a third party; these are cleanup calls, separate from remote-ASR audio upload. Their examples use `gpt-4o-mini` and `gemini-2.0-flash` respectively and label them fast/cost-effective, but include no measured latency or provider-side retention guarantees. Network and provider processing add latency and expose text to the selected service. No timing promise can be made from an 8-second client timeout—it is a maximum wait, not an expected response time.

An OpenAI-compatible endpoint could instead be self-hosted on hardware the user controls, but a remote endpoint still sends text off the dictation machine (though not necessarily to a third party). Do not use the hosted examples unless the user's privacy constraint changes. Cloud ASR alternatives such as Soniox/OpenAI are not cleanup-only and would send audio, so they are outside scope.

## Recommendations (no changes made)

1. Keep current ASR/config as-is; do not combine this experiment with the known on-demand + eager crash condition.
2. For the requested automatic list formatting and fixed self-corrections, first consider deterministic text replacements/rules. They add no model inference, preserve privacy, and are more predictable; VoxType's config includes replacement rules alongside built-in filler filtering.
3. If testing LLM cleanup, start with the official local Ollama pattern and a small non-reasoning instruct model. Use a narrowly scoped prompt, e.g. “Correct only these explicit terms; format enumerated spoken items as a Markdown list; preserve meaning/order; output only text.” Don't ask it to broadly improve style on every dictation until it proves reliable.
4. Evaluate with a fixed set of short real-world transcripts (including already-correct text, names, numbers, negations, and list items). Compare unchanged-ASR text to cleaned output, count semantic changes/manual fixes, and time stop-to-paste over multiple warm runs; separately record the first/cold run. This user's 0.46 s is the relevant baseline, not published model throughput.
5. Keep cloud scripts as reference only. They do not satisfy the current no-dictation-to-cloud requirement.

### Primary sources

- [VoxType v1.1.1 release](https://github.com/peteonrails/voxtype/releases/tag/v1.1.1)
- [VoxType v1.1.1 configuration reference](https://github.com/peteonrails/voxtype/blob/v1.1.1/docs/CONFIGURATION.md)
- [VoxType v1.1.1 Ollama cleanup script](https://github.com/peteonrails/voxtype/blob/v1.1.1/examples/ollama-cleanup.sh)
- [VoxType v1.1.1 OpenAI cleanup script](https://github.com/peteonrails/voxtype/blob/v1.1.1/examples/openai-cleanup.sh)
- [VoxType v1.1.1 Gemini cleanup script](https://github.com/peteonrails/voxtype/blob/v1.1.1/examples/gemini-cleanup.sh)
- [VoxType issue #813: firsthand streaming/stop latency and custom cleanup workflow](https://github.com/peteonrails/voxtype/issues/813)
- [VoxType issue #231: proposed GPT list/action-item workflow (proposal only)](https://github.com/peteonrails/voxtype/issues/231)
