# Image benchmark (Phase 3 input)

Date: 2026-09-28. Material: owner's photos of a Danish reading exam (Modultest.dk, Danskuddannelse 3, Læsning,
Opgave 4): page 1 = questions 1-7 (persons A/B/C), page 2 = the three texts. iPhone 17 Pro Max, 4284x4284 HEIC,
photographed at an angle with neighbouring sheets in the frame.

Ground truth (checked manually against the texts): 1 A, 2 C, 3 A, 4 C, 5 B, 6 A, 7 B.

Request: both images in one user message, order preserved, default image instruction (spec 28), WATCH_CONCISE
instructions, structured output, `store: false`, `reasoning.effort: low`, `detail: high`.

| Model | Long edge | JPEG size (2 pages) | Input tokens | Latency | Correct |
|---|---|---|---|---|---|
| gpt-6-sol | 2048 px | 1.86 MB | 6350 | 8.8 s, 6.1 s | 7/7, 7/7 |
| gpt-6-sol | 1536 px | 1.09 MB | 5878 | 4.4 s, 5.1 s, 8.9 s | 7/7 x3 |
| gpt-6-sol | 1280 px | 0.78 MB | 4190 | 6.1 s, 5.5 s | 7/7 x2 |
| gpt-6-astra | 2048 px | 1.86 MB | 6350 | 9.0 s | 7/7 |
| gpt-6-luna | 2048 px | 1.86 MB | 6350 | 6.0 s | 7/7 (verbose: 303 output tokens) |

Conclusions:
- Accuracy is not the constraint on this material; latency varies 4-9 s independent of image size (provider-side).
- **Decision: iPhone normalizes to 1536 px long edge, JPEG quality 0.8** (~0.5 MB per page): half the upload of
  2048 px, fewer tokens, margin for small print (1280 px also passed, but leaves less margin for dense pages).
- **Model stays `gpt-6-sol`.** `gpt-6-astra` brought no accuracy gain here. Re-check on harder material.

Sample answer (as shown on the Watch):
```
1 — A, Meng: ему понравилась селёдка.
2 — C, Ivan: он любит искать миндаль в десерте.
3 — A, Meng: он позже пошёл на второй рождественский ужин.
4 — C, Ivan: он сильно напился.
5 — B, Hanna: в её родной стране тоже много пьют.
6 — A, Meng: он слышал одну шутку много раз.
7 — B, Hanna: ей нравится, что после праздника коллеги ведут себя как обычно.
```

## Study materials

Date: 2026-09-28. Source: the 33 public PDFs on danskogproever.dk, "Danskuddannelse 3 - materialer til modultest"
(modules 1-4: information sheets, examples, mindmaps). Extracted text: ~10k words, ~20k tokens.

Options considered (owner asked for A + B):
- A: an exam guide written from the materials (`backend/src/main/resources/prompts/danish_exam.md`, focused on Modul 3.3).
- B: the full materials. File Search (vector store) vs. the whole text in the instructions.

Measurement (gpt-6-sol, reasoning low, text question about DU3 writing):

| Instructions | Latency | Input tokens | Cached |
|---|---|---|---|
| Watch rules only | 5.9 s | 271 | 0 |
| + full materials, first call | 4.5 s | 20 561 | 0 |
| + full materials, repeated | 5.8 s | 20 561 | 20 558 |

Decision: **B = full text as a stable instruction prefix** (prompt caching), not File Search: no measurable latency,
~$0.004 per cached request, the model sees everything (no retrieval misses), nothing is stored at OpenAI.
Revisit File Search if a knowledge pack grows beyond ~100k tokens.

The texts are third-party documents and are not stored in git: `tools/knowledge/fetch-danish-du3.sh` rebuilds
`knowledge/danish-du3/corpus.md`, `deploy/deploy.sh` copies it to the server (read-only volume).
Only conversations created as "Danish exam" use it (`Conversation.Mode` -> `ResponseMode.DANISH_EXAM`).

Server check: "Сколько времени на чтение и сколько слов?" -> 3.3 answers (50 min, min. 90 words), 16.4 s cold, 7.2 s warm.
