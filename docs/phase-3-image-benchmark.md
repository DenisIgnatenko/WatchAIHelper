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
