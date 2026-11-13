# Velora Lens

Lens adds local file, project, configuration, photo and video search to the launcher.
It is off by default. Existing app search and special prefixes work independently.
**Settings → Search** has separate switches for **AI in search** and
**Search across your files**. Both start off. Turning off file search cancels
queries, disconnects the shell and locks the index, stopping background indexing.
The saved index and selected folders are kept.

**Files and folders → Search by meaning** and **Indexing → Photos and videos**
are also off by default. Enable them explicitly to prepare vector embeddings or
analyse media. Turning off search by meaning stops neural queries and vector
preprocessing; ordinary name and indexed-text search remain available.
Existing explicit backend preferences are preserved on upgrades.

## Setup

1. Open **Settings → Search → Velora Lens** and enable search.
2. Select **Set up Lens**. Settings installs missing components, prepares the
   search service and local models, and shows completed steps, elapsed time,
   download bytes and verified model parts. System packages
   use a Polkit password dialog; no terminal is required. Models need about 2.5 GB
   plus temporary preparation space. Personal files are never uploaded.
   Setup continues if Settings closes. Cancel and retry are available on the page;
   a package-manager transaction finishes before cancellation takes effect.
3. If the index is locked, select **Unlock index** to open the system keyring
   dialog. Lens never creates an unencrypted fallback index.
4. Select **Add your first folder** and choose folders in the native picker.
   Include Documents, Projects, Pictures, Videos or specific configuration folders.
   Changes save immediately; exclusions and removal use the same page.
5. Leave the computer plugged in and idle for two minutes. Names are available
   first; contents and embeddings follow. Open search with `Super`.
   To finish indexing while using the computer, enable **Fast indexing** under
   **Indexing**. It uses up to half the available CPU threads (at least two where
   available, at most eight), instead of the normal two-thread limit. This can
   increase heat and fan noise. Both modes pause on battery, manual pause or
   screen lock. The option is off by default and saved in the encrypted index.
   **All in** uses every CPU thread available to the service, with no eight-thread
   cap and no idle wait. Press **Stop All in** to return to the previous normal or
   fast mode. Battery, manual pause, and screen lock still pause content work.

Small configuration files (up to 128 KiB), notebooks and text notes (up to 1 MiB)
get scrubbed text search during discovery; their semantic embeddings follow in the
selected indexing mode. Notebook cell boundaries are preserved, and ordinary
discussion of tokens remains searchable. Credential assignments are scrubbed.
Parser upgrades refresh existing text while retaining unchanged embeddings.
Discovery reserves
catalogue space for folders, configurations and documents before media files;
content indexing also prioritizes configurations and documents. Lua files under
`.config` count as configuration files. Configuration queries combine application
paths with file contents, including common keyboard keys such as `kb_layout`.
Explicit configuration/file-type queries put matching Lens results before loose
application-name matches. A symlinked configuration directory can be added as its
own source; selecting a subfolder of a large folder awaiting review indexes only
that subfolder, without approving the whole parent.

Try `папка где я делал DL сегодня`, `шаад`, `где настраивал горячие клавиши`,
`shad nlp hw1`, `velora folder hupr config`, `фото собака на снегу`, or
`видео синий квадрат`. Clues can be split between project folders, parent paths,
filenames and indexed content; a filename does not need to contain the request.
`folder` and `config` combine to find folders containing configuration files.
Results explain their matches, spelling repairs and any missing clues;
videos open in mpv at the selected frame's timestamp.

Settings lists the selected folders with their full paths beside the progress,
including a button to add a folder. Subfolders are included subject to exclusions.
With no selected folders, it shows applications only and no file progress bar.
Application counts are separate from processed/total items in selected folders,
ready, waiting and skipped counts. Older services label their combined counts as
files and applications. The current folder and file are shown during processing
(with a saved video checkpoint when available). During discovery it
shows the number found; a percentage appears once the total is known. Processed
includes skipped items, which retain name search. Setup step counts are separate
from download progress because the steps take different amounts of time.

`velora-searchd status` also reports progress. `velora-searchd check-models` verifies
both embedding spaces and the relevance model inside the production sandbox.
To add the reranker to an existing model bundle without rebuilding embeddings:
`python3 tools/velora-searchd/python/reranker.py --output ~/.local/share/velora-lens/models`.

## Sources and limits

Supported content includes UTF-8 text, Markdown, source code, JSON/YAML/TOML/INI,
notebook cell sources, text-layer PDFs, common raster images and videos. Notebook
code is never executed; binary outputs are ignored. Other files have name search.

Symlinks are not traversed. Dependencies, generated output, caches, credential
directories, `.env` files and browser profiles are excluded. This includes
`node_modules`, `.venv`, `.next`, package-manager and test caches, and build output
such as `target`, `build`, `dist` and `artifacts`. Python and Conda environments
are also recognized by `pyvenv.cfg` and `conda-meta`, regardless of their folder
name. Installed Python runtimes are detected by their executable and shared library;
TeX Live trees are recognized by `tlpkg/texlive.tlpdb`. CMake output directories
are detected by `CMakeCache.txt` together with `CMakeFiles`, regardless of their name.
Application caches and browser storage under `.config` are excluded while
editor settings, keybindings and snippets remain searchable. Excluded trees
do not consume catalogue slots, extraction jobs or directory watches. On unlock
and rescan, previously indexed excluded files and their derived data are removed
automatically.

Project `.gitignore` and `.ignore` files inside selected sources also exclude
generated copies and project-specific caches. Nested rules, wildcards and `!`
exceptions are supported; exceptions cannot override credential/environment
exclusions or re-include children of an excluded directory. Ignore files are not
followed through symlinks, and global Git settings outside selected sources are
not read. Rule changes reconcile existing entries and directory watches.

Folders containing at least 1,000 NumPy arrays (`.npy`/`.npz`, combined) keep
their folder, documentation and metadata in search, but omit individual arrays
by default. Smaller collections remain searchable by filename. Under **Indexing →
Dataset folders**, mark data collections whose individual images and binary
samples should also be omitted, regardless of their count or directory depth.
The folders themselves, code, notebooks, descriptions, manifests and tabular
metadata remain searchable. This rule only applies to explicitly listed dataset
folders inside selected sources; ordinary photo libraries are unaffected. The
list is saved in the encrypted index, and entries can be added or removed in Settings.
**Individual dataset samples** enables sample filenames and media search again,
subject to source choices and the catalogue limit. No array contents are read to
detect large collections. Changing these choices prunes old sample entries and
preserves embeddings of other files. The 100,000-object
limit includes folder entries and applications; it is a ceiling, not a target.

For on-demand catalogue accounting, run `cargo run --release --locked
--manifest-path tools/Cargo.toml -p velora-searchd --example index_usage`. This
reads the encrypted database without modifying it and reports counts by source,
extension and large folder, including entries rejected by the current rules.
It does not load models or print the index key or file contents.

Folders with at least 10,000 eligible files require a choice in Settings → Search.
Lens shows the full path, a lower-bound file count after automatic exclusions,
and **Include in search** / **Exclude folder** buttons. Until a choice is made,
that subtree is held out of the index; other folders continue indexing. Counts
stop at the threshold to avoid traversing huge repositories just to show a warning.
Repositories are reviewed as a whole, while ordinary directories are checked
from their children first. Choices are saved in the encrypted index and survive
restart. Excluded choices appear under **Excluded folders** and can be removed
there to review the folder again. Inclusion still obeys automatic exclusions and
the overall catalogue limit.

Known secret-bearing lines and indented blocks are removed before text and
embedding storage. This is
not a universal secret detector; add exclusions for other private directories.

| Resource | Initial limit |
| --- | --- |
| Catalogue | 100,000 objects |
| Content | 500,000 chunks; 5 GiB logical storage, excluding models |
| Text | 2 MiB input; 128,000 extracted characters |
| PDF | First 200 pages with an existing text layer |
| Image | 64 MiB input; 40 million pixels |
| Video | 24 hours; one frame per ten seconds; near-duplicate filtering |
| Extraction | Memory/CPU limits and a 120-second job timeout |

Video work is checkpointed in two-minute batches. Speech and short events between
sampled frames are not indexed. Unsupported or failed files keep name search and
appear in the skipped count.

Activity lasts 90 days and comes from Lens opens, terminal directory changes and
available local `recently-used.xbel` **visited** timestamps. Hooks never read shell
commands or history. Apps without recent-file integration are not comprehensively
tracked. Modification time never substitutes for evidence of activity.

Disabling activity clears its journal. Excluding a folder removes its metadata,
text, vectors and frames. Disabling media indexing removes indexed media content
while retaining names. Removing every source clears personal-file search.

## Architecture and protection

The Rust user service exposes a same-UID, mode-0600 Unix socket under
`$XDG_RUNTIME_DIR/velora-lens`. Only the attached main shell controls lock, idle and
power state. Losing the shell connection locks the index.

SQLCipher encrypts metadata, FTS text, history, FP16 vectors, thumbnails and HNSW
snapshots in `$XDG_DATA_HOME/velora-lens/index.db`. Its random 256-bit key lives in
the default Secret Service collection, never in arguments or config files. SQLite
temporary storage is in memory; journal pages are encrypted; core dumps are disabled.
This protects stored index data, not a compromised session or unencrypted OS swap.

Screen lock cancels requests, closes the database, discards workers/indexes and
clears private results. Unlock reconciles metadata. There is no plaintext vector
index, thumbnail cache or query log.

Bubblewrap gives the extractor one read-only file, no network and no home-directory
access. Inference gets only text/pixels over pipes, read-only models and its private
runtime. Sandbox failure stops the job; there is no unprotected fallback. Model
preparation is a separate networked process; inference never downloads anything.

Names use character/bigram candidates, edit distance, layout and transliteration
variants. Alias expansion preserves the complete query. FTS5 searches names,
directory paths and contents, allowing query terms to occur in different fields.
The immediate pass also intersects per-word postings across names, ancestors and
scrubbed passages. An encrypted vocabulary with deletion signatures repairs one
insertion, deletion or substitution (four letters or more), and adjacent
transpositions (three letters or more), without scanning files or loading a model.
Each input term gets at most four spelling alternatives; numbers stay literal.
Up to sixteen term groups, 64 vocabulary candidates per group and 256 resulting
objects bound this stage. Existing FTS remains available for phrase alternatives
and words beyond the per-file vocabulary budget (4096 metadata and 4096 content
tokens). No project names from the examples are special-cased by this mechanism.

The object type and content category are separate facets: `folder config` ranks
folders by matching configuration descendants, preserving the descendant's
evidence. Project constraints apply independently of configuration type. Complete
postings matches avoid a redundant broad content search. Partial lexical results
are exposed only within an identified location, with at least three clues and
two-thirds coverage; they rank below complete matches and list missing terms.
They never relax numbered identifiers or explicit location/type constraints.
Only exact or transliterated folder anchors establish implicit hard scopes;
spelling hypotheses remain ranking/retrieval evidence and cannot exclude a
stronger content match elsewhere. Absolute and `~/` paths, including quoted paths
with spaces, are extracted before query normalization and validated against the
selected sources. They remain hard constraints even when there are no matches;
an inaccessible or excluded explicit path produces an error, not a global search.
Numbers in a source-root or scope prefix cannot satisfy an assignment number.

Schema 3 upgrades the encrypted vocabulary once from already indexed data; it
does not require content extraction or new embeddings. Exclusion, deletion and
replacement remove corresponding spelling data. Query/spelling caches are
bounded to 32/128 entries, invalidated by index writes, and discarded on lock.
Activity expiration runs at unlock and recording, outside the keystroke path.
Russian Snowball stemming handles inflected terms without treating a short stem
as an arbitrary substring. Format words such as `pdf` and `пдф` filter extensions.
Both launcher styles display the file path below each filename.
Short identifiers (up to three characters, without a phrase expansion) use
immediate lexical search. Adjacent transpositions are accepted, but typo repair
is not stacked on top of keyboard-layout repair. Plain words are not submitted
to the calculator. Explicit math prefixes still allow symbolic expressions.

Text retrieval combines FTS5 with multilingual E5 / USearch candidates. An installed
application description can connect a configuration query to the corresponding
directory under `.config`, even when the app name does not describe its purpose.
Application retrieval embeds the subject separately; document retrieval and
reranking retain the query's subject and intent. Folder names at any indexed depth
can limit candidates to that location, including transliterated names. Compatible
ancestor names narrow one another. Numbered identifiers split letters and digits,
normalize leading zeros, and combine filename and parent context: `hw1` can match
`task1/homework.ipynb`, while `hw10` remains distinct. Numbered label abbreviations
use ordered letters; they are not a list of project-specific exceptions.
Browser copy suffixes such as `(2)` do not count as assignment numbers. Generic
structured-data extensions (JSON/YAML/TOML) count as configuration only when the
name or location identifies settings, so datasets do not compete as app configs.
Explicit project constraints are removed from the neural topic query; config
queries retain application context for interpreting terse keys. Up to 20,000
vectors in a scoped/type-filtered search are compared directly, avoiding a rebuild
of the global ANN index during background extraction. Discovery yields to active
queries, and complete name/number navigation skips content ranking and inference.
A local multilingual MiniLMv2 cross-encoder then compares the complete original query against up to
32 candidate passages and their paths, in batches of four (384 tokens maximum).
The document's relative source path supplies context without home-directory noise.
The candidate budget reserves space for both lexical and neural retrieval, including
application-associated configurations, so frequent terms cannot crowd out semantic candidates.
A small logistic model combines E5 similarity, its margin over other documents,
and the cross-encoder score. It is fitted on synthetic dev projects; personal
queries are neither logged nor used for training. `evaluation/calibrate.py`
reproduces the checked-in coefficients and reports held-out results. This small
calibration corpus does not guarantee relevance on arbitrary personal collections.
The cross-encoder orders accepted results, with a bounded confidence contribution
for close scores. Document roles (assignment, report, lecture) and complete names
supply navigation evidence. Path embeddings keep name relevance available even
after body content is indexed. Weak neural matches are filtered; exact lexical matches remain usable for code
identifiers and filenames. If reranking is unavailable, search keeps lexical
matches instead of exposing an unverified nearest-neighbour list.

Images use a separate SigLIP 2 space, selected by photo/video intent; ordinary
text queries do not inject unrelated nearest images. Folder results aggregate
descendant evidence and favor project roots, retaining the actual evidence path
for neural scoring. Empty OCR is excluded from text embeddings. Unapproved or
excluded sources are not searched, even when their contents would answer a query.

Models currently use FP32 ONNX; vectors and HNSW use FP16. INT8 needs a separate
held-out quality comparison before adoption. Weights are revision-pinned,
exported without remote code, compared with PyTorch outputs and checksum-verified.
The reranker uses its publisher's ONNX export, pinned by revision and SHA-256.
Adding it preserves the existing embedding revision and requires no reindex.

Watchers cover accepted directories only. Changes are coalesced; moves retain
identity; hashes avoid redundant text embedding. Content work pauses on battery
and, in normal mode, on user activity. Fast indexing continues during user activity
with a larger CPU thread budget; switching modes restarts the worker with the new
budget. Interactive search can run on battery with the normal thread budget. Query inference has a
250 ms debounce; obsolete requests are cancelled. Idle models and indexes unload
after a timeout, checked by periodic housekeeping.

## Protocol and tests

Protocol 1 uses JSON lines: `{id, method, params}` requests and
`{type:"response", id, ok, result|error}` responses after `hello`. Methods include
`attach`, `context`, `status`, `configure`, `search`, `cancel`, `record`, `resolve`,
`apps`, `unlock` and `rescan`. The explicit `unlock` action opens a system keyring
prompt only while the main shell reports an unlocked desktop. Configuration
replaces the whole settings object and stays
inside the encrypted database. Results include ID, kind, path/desktop ID, reason,
snippet, optional activity time, video timestamp and in-memory preview. Additive
fields `partial`, `matched_terms`, `unmatched_terms` and `corrections` (objects
with `from`/`to`) explain immediate contextual matches. `query.content_kind`
preserves the content facet independently of `query.kind`; `query.paths` records
explicit path constraints. Opening
revalidates scope and access; document content never becomes a shell command.
For a one-off diagnostic, `search` accepts `explain:true` and returns candidate
scores and lexical/retrieval/reranking timings. It does not write a query log.

```sh
cargo test --locked --manifest-path tools/Cargo.toml -p velora-searchd
python3 -m unittest discover -s tests -p 'test_lens.py' -v
cargo test --locked --manifest-path tools/Cargo.toml -p velora-searchd \
  --test functional -- --ignored --nocapture
cargo run --release --locked --manifest-path tools/Cargo.toml \
  -p velora-searchd --example evaluate > evaluation.json
cargo run --release --locked --offline --manifest-path tools/Cargo.toml \
  -p velora-searchd --example lexical_benchmark -- 10000 100000 > lexical-benchmark.json
```

Service tests use a private D-Bus bus and temporary files. The opt-in real-model
test in `tools/velora-searchd/tests/models.rs` also needs an exported bundle,
`VELORA_LENS_PYTHON` and `VELORA_LENS_FIXTURES`. Generate fixtures with
`python tools/velora-searchd/evaluation/make_media.py /tmp/lens-fixtures` using
the Lens Python environment, then set `VELORA_LENS_FIXTURES=/tmp/lens-fixtures`
and run the Cargo test with `--test models -- --ignored --nocapture`.
The generator needs ffmpeg. Tests require local sockets and user
namespaces, but never change the real desktop or keyring.

The functional matrix checks short identifiers, numbered assignments, nested
folders, natural-language requests, configurations, application launch intent,
and absent results before and after content indexing. It uses synthetic files
and the installed local models. Set `VELORA_LENS_EVAL_REPORT` to save its report.
QML tests cover opening resolved files/folders, desktop entries and video offsets,
including encoded paths, stale results and screen-lock cancellation.
The unignored contextual tests cover both compound examples, unseen project
names, reordered clues, mixed scripts, path/content typos, exact assignment
numbers, partial explanations, vocabulary deletion and cache invalidation.
They also run the existing metadata navigation matrix without starting a model.

`lexical_benchmark` creates private synthetic 10K/100K-object indexes and measures
the complete lexical `Engine` call, including scope/access checks, with a fresh
connection, warm index without result caches, and cached repeated requests.
Connection startup is reported separately. OS page caches are not cleared.
It reports Recall@5/nDCG@10 on eight contextual cases, RSS and one second of idle
process CPU; this is not a whole-desktop or battery-energy measurement.

Recorded on 2026-11-06 with an AMD Ryzen AI 9 HX 370, release build:

| Synthetic objects | First query, fresh connection p95 | Warm index, query caches cleared p95 | Repeated cached query p95 | RSS |
| --- | --- | --- | --- | --- |
| 10,000 | 1.83 ms | 1.03 ms | 0.165 ms | 26,280 KiB |
| 100,000 | 8.41 ms | 5.97 ms | 0.196 ms | 26,412 KiB |

All eight benchmark cases ranked the expected object first (Recall@5 and
nDCG@10 = 1.0); that score describes this small fixture, not arbitrary collections.
The worker stayed unloaded; measured idle CPU was below 0.02% during the one-second
sample. Raw data is in
[`lexical-benchmark.json`](../tools/velora-searchd/evaluation/lexical-benchmark.json).
Cold OS caches, IPC/rendering latency and whole-device energy are not measured.

The real offline-model regression additionally verifies
`шад обработка языка первая домашка` against English-only NLP coursework, with
wrong-project and assignment-10 distractors. Its report is
[`neural-validation.json`](../tools/velora-searchd/evaluation/neural-validation.json)
(regenerate with `VELORA_LENS_NEURAL_REPORT` while running that ignored test).
The 66-scenario metadata/indexed functional matrix also passes with the installed
models. Semantic refinement can take hundreds of milliseconds when a model is
cold or the candidate set is broad; the immediate lexical UI does not wait for it.

Evaluation builds temporary English documents and runs 200 synthetic RU/EN
queries, including typos and activity constraints. Dev/test splits use different
projects. It reports lexical/hybrid Recall@5, nDCG@10 and p95 latency. This is a
regression corpus, **not** a personal 100,000-file or battery-life benchmark.
Pass `-- --idle` to the evaluation example to measure RSS and CPU during a
30-second idle window after model/index eviction. This takes about two minutes;
it checks eviction, not whole-device energy use. Measure a representative
collection separately before publishing battery-life or scale claims.
