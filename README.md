# Labelling bug-fixing commits with language models: replication package

This repository contains the data, prompts, scripts and results of a study that evaluates open-weight and hosted language models as labellers of bug-fixing commits. It also contains a corpus of 33 labelled commit histories.

## Contents

```
evaluation_data/          verdicts of all labellers on the four benchmarks, SmartSHARK issue and validation data
released_corpus/          labelled commit histories of 33 open-source projects
scripts/
  commit-prompt-miner/    builds the prompts and the keyword baseline (Kotlin)
  commit_classification_prompt_executer.py
                          runs the prompts on a local model through Ollama (Python)
statistical_analysis/     R script for the statistics and figures, and its results
model-provenance.md       versions and settings of all models
LICENSE                   Apache License 2.0 (code)
DATA_LICENSE              CC BY 4.0 (data)
```

## Evaluation data

`1-mined-combined.csv` and `2-mined-combined.csv` contain one row per commit for the zero-shot prompt P1 and the few-shot prompt P2. The columns are

- `dataset`: `smartshark`, `bugsinpy`, `bugsjs` or `pybughive`
- `repo` and `hash`: project and commit
- `message`: the commit message
- `is_bugfix`: the label of the benchmark
- `isBugfix_<labeller>`: the verdict of each labeller, that is, the keyword baseline (`stemming`), the seven open-weight models, GPT-5.6 Luna at low and at high reasoning effort, and Claude Sonnet 5.5.

The files contain every labelled commit. The analysis uses 35 of the 40 SmartSHARK projects and only the commits that both prompts cover. The R script applies this selection and documents the excluded projects.

The three SmartSHARK files are extracts from release 2.2 of the SmartSHARK MongoDB data (https://smartshark.github.io/dbreleases/), which is published under CC BY 4.0. They cover the evaluated commits, and their column names and values were translated into English.

- `smartshark-issues.csv` has one row per link between an evaluated commit and an issue. `issue_type` is the type the reporter filed, `issue_type_verified` the type assigned in the manual validation (`-` if the issue was not validated), and `link_verified` states whether the link was checked by hand. Commits without a linked issue have an empty `issue_key`.
- `smartshark-validators-issues.csv` has one row per commit and issue with the decisions of the individual raters and of the committee. The columns `sherbold`, `ftrautsch` and `atrautsch` are the identifiers of the SmartSHARK raters. `bug_decision` summarises the result, for example `unanimous_bug` or `split`.
- `smartshark-validators.csv` has one row per commit. `gt_certainty` summarises how its label came about: `sure` if the raters agreed, `close` if they disagreed and a committee decided, `weak` if a linked bug report has fewer than two ratings, `jira_type` if the commit links only to issue types that were not rated, and `no_issue` if it links to no issue.

## Released corpus

`released_corpus/` contains one file per project with the columns `hash` and `isBugfix_mistral-small3.2:24b`. Together they label 389,567 commits, 79,696 of them as fixes. The labels come from `mistral-small3.2:24b` with prompt P2. They are model labels and were not checked by hand.

The corpus covers these projects.

| Project | Repository | Commits | Labelled fixes |
|---|---|---:|---:|
| auth | https://github.com/AzureAD/microsoft-authentication-library-for-android | 3,057 | 237 |
| bahmni-core | https://github.com/Bahmni/bahmni-core | 2,830 | 462 |
| caldera | https://github.com/mitre/caldera | 4,534 | 462 |
| ctakes | https://github.com/apache/ctakes | 214 | 20 |
| cuckoo | https://github.com/cuckoosandbox/cuckoo | 8,063 | 1,465 |
| cve-search | https://github.com/cve-search/cve-search | 2,847 | 372 |
| ehrbase | https://github.com/ehrbase/ehrbase | 4,864 | 502 |
| equinox | https://github.com/eclipse-equinox/equinox | 9,319 | 3,034 |
| error-prone | https://github.com/google/error-prone | 7,392 | 1,113 |
| fastjson | https://github.com/alibaba/fastjson | 3,983 | 925 |
| flask | https://github.com/pallets/flask | 5,539 | 515 |
| flink | https://github.com/apache/flink | 38,063 | 6,630 |
| honeyscanner | https://github.com/honeynet/honeyscanner | 41 | 0 |
| IntelOwl | https://github.com/intelowlproject/IntelOwl | 3,115 | 394 |
| j2cl | https://github.com/google/j2cl | 8,227 | 823 |
| jdt | https://github.com/eclipse-jdt/eclipse.jdt.core | 27,805 | 12,321 |
| keycloak | https://github.com/keycloak/keycloak | 31,441 | 5,090 |
| lucene | https://github.com/apache/lucene | 39,310 | 9,395 |
| mylyn | https://github.com/eclipse-mylyn/org.eclipse.mylyn | 22,241 | 5,059 |
| next | https://github.com/vercel/next.js | 34,502 | 3,997 |
| nomulus | https://github.com/google/nomulus | 5,310 | 512 |
| openhospital-core | https://github.com/informatici/openhospital-core | 2,360 | 320 |
| openmrs-core | https://github.com/openmrs/openmrs-core | 13,058 | 3,556 |
| pde | https://github.com/eclipse-pde/eclipse.pde | 20,478 | 6,855 |
| query | https://github.com/TanStack/query | 4,842 | 498 |
| sigma | https://github.com/SigmaHQ/sigma | 16,815 | 937 |
| snow-owl | https://github.com/b2ihealthcare/snow-owl | 16,603 | 2,339 |
| spiderfoot | https://github.com/smicallef/spiderfoot | 3,742 | 689 |
| synthea | https://github.com/synthetichealth/synthea | 4,978 | 741 |
| termux | https://github.com/termux/termux-app | 1,505 | 279 |
| tomcat | https://github.com/apache/tomcat | 28,758 | 7,702 |
| yeti | https://github.com/yeti-platform/yeti | 3,432 | 511 |
| zaproxy | https://github.com/zaproxy/zaproxy | 10,299 | 1,941 |

## Labelling pipeline

The pipeline has two stages. The prompt miner reads a Git repository and writes, for every commit, the verdict of the keyword baseline to `<repo>-bugfixes.csv` and a ready-to-run prompt to `<repo>-commit-prompts.json`. It makes no model calls. The executer then sends the prompts to a local model through Ollama and adds the verdicts to the same CSV, keyed on the commit hash. The prompt texts are defined in `scripts/commit-prompt-miner/src/main/kotlin/org/anonymous/commitminer/OllamaPrompt.kt`.

### Prompt miner

The miner needs a JDK 23, which the Gradle wrapper provisions if it is missing.

```bash
cd scripts/commit-prompt-miner
./gradlew shadowJar
java -jar build/libs/shadow-*.jar -r <repo> -o <out-dir> [options]
```

| Option | Default | Meaning |
|---|---|---|
| `--repository`, `-r` | required | Git repository (working tree or a directory containing `.git`) |
| `--out-dir`, `-o` | required | output directory, created if missing |
| `--top-files`, `-n` | 10 | maximum number of changed files per prompt, largest changes first |
| `--max-diff-lines`, `-l` | 15 | maximum number of diff lines per file, `0` shows only the counts of added and removed lines |
| `--with-reason` | off | also ask the model for a short reason |
| `--hashes` | none | text file with one commit hash per line, to mine only these commits |

P1 used the defaults (`-n 10 -l 15`) and P2 used `-n 10 -l 50`. In the reported runs, diff lines longer than 300 characters were also cut to 300 characters. This cut is not part of the current version of the miner.

### Prompt executer

The executer needs Python 3.6 or later and no third-party packages, and a running Ollama instance with the model pulled (`ollama pull <model-tag>`).

```bash
python3 scripts/commit_classification_prompt_executer.py -p <repo>-commit-prompts.json -c <repo>-bugfixes.csv -m <model-tag>
```

| Option | Default | Meaning |
|---|---|---|
| `--prompts`, `-p` | required | prompts JSON written by the miner |
| `--csv`, `-c` | required | CSV to update, created if missing |
| `--model-version`, `-m` | `qwen3.5:9b` | Ollama model tag |
| `--base-url` | `http://localhost:11434` | Ollama address |
| `--num-predict` | value from the prompt file | maximum number of output tokens |
| `--num-ctx` | value from the prompt file | context window |
| `--request-timeout` | 120 | timeout per prompt in seconds |

The decoding settings (temperature 0, top-p 0, top-k 1) are written into every prompt by the miner and passed on unchanged, so a repeated run returns the same verdicts. The reported runs used a context window of 4,096 tokens for P1 and 16,384 tokens for P2. The model builds and the settings of the hosted models are listed in `model-provenance.md`. The hosted models received the same prompts through the providers' batch APIs, and their verdicts are part of the evaluation files.

## Statistical analysis

`statistical_analysis/analysis_anonym_ver3_6_1.r` computes all metrics, tests and figures. It was tested with R 4.3.3 and needs the packages below. PMCMR must be version 4.3, because later versions no longer contain the Nemenyi test that the script uses.

```r
install.packages(c("dplyr", "tidyr", "ggplot2", "ModelMetrics", "reshape2"))
install.packages("https://cran.r-project.org/src/contrib/Archive/PMCMR/PMCMR_4.3.tar.gz", repos = NULL, type = "source")
install.packages("remotes")
remotes::install_github("b0rxa/scmamp")
```

Run the script from within `statistical_analysis/`, once with `PROMPT <- 1` and once with `PROMPT <- 2` at the top of the file.

```bash
cd statistical_analysis
Rscript analysis_anonym_ver3_6_1.r
```

The results for both prompts are already in `statistical_analysis/results/`.

| File | Content |
|---|---|
| `P*_smartshark_metrics.csv` | precision, recall, F1 and MCC on SmartSHARK, recall on the fix-only benchmarks |
| `P*_friedman.txt`, `P*_avg_ranks.csv` | Friedman test, Kendall's W, Nemenyi critical difference and average ranks by per-project MCC |
| `P*_cd_diagram.pdf` | critical-difference diagram |
| `P*_heatmap_mcc.pdf`, `P*_heatmap_mcc_centered.pdf` | MCC per project and labeller, absolute and relative to the project mean |
| `heatmap_mcc_both_prompts.pdf`, `heatmap_mcc_centered_both_prompts.pdf` | the same for both prompts in one figure, with the order of P2 in both panels (Figures 4 and 5 of the paper) |
| `P*_rq3_by_validation_status.csv` | share of commits each labeller calls a fix, by how the SmartSHARK label came about |
| `P*_rq3_errors_on_disputed.csv` | share of each labeller's errors on commits whose raters disagreed |
| `P*_rq3_by_issue_type.csv` | false-positive rate of the five strongest open-weight models by linked issue type and keyword match |
| `P*_rq3_bug_reports.csv` | how often each labeller calls commits linked to an issue filed as a bug a non-fix, and how many of these the raters re-typed |

## Licences

The code is licensed under the Apache License 2.0 and the data under CC BY 4.0. The SmartSHARK extracts remain under the CC BY 4.0 licence of SmartSHARK. Commit messages remain subject to the licences of their projects.

## Acknowledgements

We thank the maintainers of SmartSHARK, BugsInPy, BugsJS and PyBugHive for making their data available.
