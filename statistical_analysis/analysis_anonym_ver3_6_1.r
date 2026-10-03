
library(dplyr)
library(tidyr)
library(ggplot2)
library(ModelMetrics)

DATA_DIR <- "../evaluation_data"
OUT_DIR  <- "results"
dir.create(OUT_DIR, showWarnings = FALSE)

# prompt: 1 or 2
PROMPT <- 1

p1 <- read.csv(file.path(DATA_DIR, "1-mined-combined.csv"))
p2 <- read.csv(file.path(DATA_DIR, "2-mined-combined.csv"))
run1 <- if (PROMPT == 1) p1 else p2

# smartshark projects not used in the evaluation
EXCLUDE <- c("directory-fortress-core", "commons-imaging", "falcon", "xerces2-j", "systemml")

# commits covered by both prompts
common <- intersect(paste(p1$repo, p1$hash), paste(p2$repo, p2$hash))
run1 <- run1[!(run1$repo %in% EXCLUDE) & paste(run1$repo, run1$hash) %in% common, ]

#remove pybughive salt --> no labels available
run1 <- run1[run1$is_bugfix != "",]

#transform labels into bool
for (i in 5:ncol(run1)){
  run1[,i] <- as.logical(run1[,i])
  
}


# names for the figures
display_names <- c(
  "stemming"             = "keyword baseline",
  "codegemma.7b"         = "codegemma:7b",
  "gemma4.12b"           = "gemma4:12b",
  "codestral.22b"        = "codestral:22b",
  "mistral.small3.2.24b" = "mistral-small3.2:24b",
  "qwen3.coder.30b"      = "qwen3-coder:30b",
  "qwen3.6.35b"          = "qwen3.6:35b",
  "qwen3.5.122b"         = "qwen3.5:122b",
  "gpt.5.6.luna.low"     = "GPT-5.6 Luna (low)",
  "gpt.5.6.luna.high"    = "GPT-5.6 Luna (high)",
  "claude.sonnet.5.5"    = "Claude Sonnet 5.5")

# helpers
my_accuracy <- function(x, y){
  res <- x == y
  return(round(mean(res), 3))
}


# 1 - Performance metrics overall
y <- run1$is_bugfix

all_names <- c()
acc <- c()
prec <- c()
rec <- c()
f1 <- c()
mccs <- c()

for(i in 6:ncol(run1)){
  X <- run1[,i]
  
  name_temp <- colnames(run1)[i]
  all_names <- c(all_names, unlist(strsplit(name_temp, "_"))[2])
  
  acc <- c(acc, my_accuracy(X,y))
  prec <- c(prec, round(precision(y,X), 3))
  rec <- c(rec, round(recall(y,X), 3))
  f1 <- c(f1, round(f1Score(y,X), 3))
  mccs <- c(mccs, round(mcc(y, X, cutoff = 0.5), 3))

}

results <- data.frame(
  Model = all_names,
  Accuracy = acc,
  Precision = prec,
  Recall = rec,
  F1Score = f1,
  MCC = mccs
)
results <- results[order(results$F1Score, decreasing = TRUE),]

# 1.1 - smartshark metrics, recall on the other datasets
smsh <- run1[run1$dataset == "smartshark", ]
fixonly <- run1[run1$dataset != "smartshark", ]
results_smsh <- data.frame()
for(i in 6:ncol(run1)){
  X <- smsh[,i]
  ys <- smsh$is_bugfix
  results_smsh <- rbind(results_smsh, data.frame(
    Model = unlist(strsplit(colnames(run1)[i], "_"))[2],
    Precision = round(precision(ys, X), 3),
    Recall = round(recall(ys, X), 3),
    F1Score = round(f1Score(ys, X), 3),
    MCC = round(mcc(ys, X, cutoff = 0.5), 3),
    RecallFixOnly = round(mean(fixonly[,i]), 3)))
}
results_smsh <- results_smsh[order(results_smsh$MCC, decreasing = TRUE),]
print(results_smsh)
write.csv(results_smsh, file.path(OUT_DIR, paste0("P", PROMPT, "_smartshark_metrics.csv")), row.names = FALSE)


# 2 - Model per dataset+repo metrics

all_results <- list()
iter <- 1
for(i in 6:ncol(run1)){
  
  name_temp <- colnames(run1)[i]
  name <- unlist(strsplit(name_temp, "_"))[2]
  
  temp_r <- run1 %>%
    group_by(dataset, repo) %>%
    summarise(
      accuracy  = my_accuracy(is_bugfix, .data[[name_temp]]),
      precision = precision(is_bugfix, .data[[name_temp]]),
      recall    = recall(is_bugfix, .data[[name_temp]]),
      f1        = f1Score(is_bugfix, .data[[name_temp]]),
      mcc       = mcc(is_bugfix, .data[[name_temp]], cutoff = 0.5)
      ) %>%
    ungroup()
  
  names(temp_r)[-(1:2)] <- paste0(name, "_", names(temp_r)[-(1:2)])
  
  all_results[[iter]] <- temp_r
  iter <- iter + 1
}

results1 <- Reduce(function(x, y) merge(x, y, by = c("dataset", "repo"), all = TRUE), all_results)

metrics <- results1 %>%
  gather(key = "key", value = "value", -dataset, -repo) %>%
  separate(key, into = c("predictor", "metric"), sep = "_(?=[^_]+$)") %>%
  spread(metric, value)

macrof1 <- metrics %>%
  group_by(predictor) %>%
  summarise(
    mean_f1 = mean(f1, na.rm = TRUE),
    sd_f1   = sd(f1, na.rm = TRUE),
    min_f1  = min(f1, na.rm = TRUE),
    max_f1  = max(f1, na.rm = TRUE)
  ) %>%
  arrange(desc(mean_f1))

macrof1[,sapply(macrof1, is.numeric)] <- sapply(macrof1[,sapply(macrof1, is.numeric)], round, 3)


counts <- count(run1, dataset, repo)

# 2.1 - micro vs macro (overall f1 vs avg. per repo f1)
f1comp <- merge(results[,c(1,5)], macrof1[,c(1,2)], by.x = "Model", by.y = "predictor")
f1comp <- f1comp[order(f1comp$F1Score, decreasing = TRUE),]
#### This is not useful because we have only one repo labeled


# 2.2 - per dataset view, not per repo view
dsres <- metrics %>% group_by(dataset, predictor) %>%
  summarise(mean_f1 = round(mean(f1, na.rm = TRUE), 3)) %>%
  arrange(dataset, desc(mean_f1)) %>%
  ungroup()

ord <- c("mistral.small3.2.24b","qwen3.6.35b","qwen3.5.122b",
         "qwen3.coder.30b","gemma4.12b","codestral.22b",
         "codegemma.7b","stemming",
         "gpt.5.6.luna.low","gpt.5.6.luna.high","claude.sonnet.5.5")

dsresWide <- dsres %>%
  spread(key = predictor, value = mean_f1) %>%
  select(dataset, one_of(ord))


# 2.3 - per repo view only in smartshark (only with negative labels)
smsh_only <- results1 %>%
  filter(dataset == "smartshark") %>%
  gather(key = "key", value = "value", -dataset, -repo) %>%
  separate(key, into = c("predictor", "metric"), sep = "_(?=[^_]+$)") %>%
  spread(metric, value)

macrof_smsh <- smsh_only %>%
  group_by(predictor) %>%
  summarise(
    mean_f1 = mean(f1, na.rm = TRUE),
    sd_f1   = sd(f1, na.rm = TRUE),
    min_f1  = min(f1, na.rm = TRUE),
    max_f1  = max(f1, na.rm = TRUE),
    mean_prec = mean(precision, na.rm = TRUE),
    sd_prec   = sd(precision, na.rm = TRUE),
    min_prec  = min(precision, na.rm = TRUE),
    max_prec  = max(precision, na.rm = TRUE),
    mean_rec = mean(recall, na.rm = TRUE),
    sd_rec   = sd(recall, na.rm = TRUE),
    min_rec  = min(recall, na.rm = TRUE),
    max_rec  = max(recall, na.rm = TRUE)
  ) %>%
  arrange(desc(mean_f1))

macrof_smsh[,sapply(macrof_smsh, is.numeric)] <- sapply(macrof_smsh[,sapply(macrof_smsh, is.numeric)], round, 3)


# 2.4 - per repo difficutly figure
# undefined MCC counts as 0
ss <- metrics %>% filter(dataset == "smartshark") %>%
  mutate(mcc = ifelse(is.nan(mcc), 0, mcc))

# order predictors by mean MCC, repos by mean MCC
pred_order <- ss %>% group_by(predictor) %>%
  summarise(m = mean(mcc, na.rm = TRUE)) %>% arrange(m) %>% pull(predictor)
repo_order <- ss %>% group_by(repo) %>%
  summarise(m = mean(mcc, na.rm = TRUE)) %>% arrange(m) %>% pull(repo)

ss <- ss %>%
  mutate(predictor = factor(predictor, levels = pred_order),
         repo      = factor(repo,      levels = repo_order))

# --- Version A: absolute MCC ---
pA <- ggplot(ss, aes(repo, predictor, fill = mcc)) +
  geom_tile(color = "white", linewidth = 0.3) +
  scale_fill_viridis_c(option = "magma", limits = c(min(0, min(ss$mcc)), 1)) +
  scale_y_discrete(labels = display_names) +
  labs(x = NULL, y = NULL, fill = "MCC") +
  theme_minimal(base_size = 7) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
print(pA)
ggsave(file.path(OUT_DIR, paste0("P", PROMPT, "_heatmap_mcc.pdf")), pA, width = 5.4, height = 3.1, device = cairo_pdf)


# --- Version B: within-repo centered F1 (disagreement) ---
ss_c <- ss %>% group_by(repo) %>%
  mutate(mcc_centered = mcc - mean(mcc, na.rm = TRUE)) %>% ungroup()

pB <- ggplot(ss_c, aes(repo, predictor, fill = mcc_centered)) +
  geom_tile(color = "white", linewidth = 0.3) +
  scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b",
                       midpoint = 0) +
  scale_y_discrete(labels = display_names) +
  labs(x = NULL, y = NULL, fill = "MCC \u2212 repo mean") +
  theme_minimal(base_size = 7) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
print(pB)
ggsave(file.path(OUT_DIR, paste0("P", PROMPT, "_heatmap_mcc_centered.pdf")), pB, width = 5.4, height = 3.1, device = cairo_pdf)



# 3 - Friedman test to finally rank the models:
## ---- 1. Build the repo x model MCC matrix for smartshark, one prompt ----
## metrics = your long frame: dataset, repo, predictor, mcc

ss <- metrics %>%
  filter(dataset == "smartshark") %>%
  mutate(mcc = ifelse(is.nan(mcc), 0, mcc)) %>%
  select(repo, predictor, mcc)

## wide: rows = repositories (blocks), cols = models (treatments)
wide <- ss %>%
  spread(predictor, mcc)   # tidyr >= 1.0
## tidyr 0.8 fallback: spread(predictor, f1)

mat <- as.matrix(wide[,-1])      # numeric matrix, rows=repos, cols=models
rownames(mat) <- wide$repo

## ---- 3. Omnibus Friedman test ----
ft <- friedman.test(mat)
print(ft)
## Kendall's W
W <- unname(ft$statistic) / (nrow(mat) * (ncol(mat) - 1))
cat(sprintf("Kendall's W = %.3f\n", W))
## If p >= 0.05: STOP. No model differs; the "leading cluster" ordering
## is not statistically supported and you report that honestly.
## If p <  0.05: at least one model differs -> proceed to post-hoc.

## ---- 4. Nemenyi post-hoc (all pairwise) ----
# install.packages("PMCMRplus")
library(PMCMR)
ny <- posthoc.friedman.nemenyi.test(mat)   # matrix of pairwise p-values
print(ny)

## ---- 5. Average ranks + critical difference (for the CD diagram) ----
## ranks per repo: best MCC = rank 1 (hence the minus sign)
ranks <- t(apply(-mat, 1, rank))
avg_rank <- sort(colMeans(ranks))   # lower = better
print(round(avg_rank, 3))

k <- ncol(mat); N <- nrow(mat)
q_alpha <- qtukey(0.95, k, df = Inf) / sqrt(2)   # Nemenyi critical value
CD <- q_alpha * sqrt(k * (k + 1) / (6 * N))
cat(sprintf("k=%d models, N=%d repos, critical difference (CD) = %.3f\n",
            k, N, CD))

write.csv(data.frame(model = names(avg_rank), avg_rank = round(unname(avg_rank), 3)),
          file.path(OUT_DIR, paste0("P", PROMPT, "_avg_ranks.csv")), row.names = FALSE)
writeLines(c(sprintf("Friedman chi2(%d) = %.2f, p = %.3g", k - 1, unname(ft$statistic), ft$p.value),
             sprintf("Kendall's W = %.3f", W),
             sprintf("k = %d, N = %d, Nemenyi CD = %.3f", k, N, CD)),
           file.path(OUT_DIR, paste0("P", PROMPT, "_friedman.txt")))

library(scmamp)
mat_plot <- mat
colnames(mat_plot) <- display_names[colnames(mat)]
plotCD(as.data.frame(mat_plot), alpha = 0.05)
cairo_pdf(file.path(OUT_DIR, paste0("P", PROMPT, "_cd_diagram.pdf")), width = 12, height = 4.5)
plotCD(as.data.frame(mat_plot), alpha = 0.05)
dev.off()


# 4 - error analysis on smartshark
val <- read.csv(file.path(DATA_DIR, "smartshark-validators.csv"))
iss <- read.csv(file.path(DATA_DIR, "smartshark-issues.csv"))

pred_cols <- colnames(run1)[6:ncol(run1)]
smsh <- merge(smsh, val[, c("repo", "hash", "gt_certainty")], by = c("repo", "hash"))
strong <- c("isBugfix_qwen3.5.122b", "isBugfix_gemma4.12b", "isBugfix_mistral.small3.2.24b",
            "isBugfix_qwen3.6.35b", "isBugfix_qwen3.coder.30b")

# 4.1 - share called fix by validation status
groups <- data.frame(
  label     = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
  certainty = c("sure", "close", "close", "sure", "weak", "jira_type", "no_issue"),
  group     = c("fix, raters agreed", "fix, raters disagreed",
                "non-fix, raters disagreed", "non-fix, raters agreed",
                "non-fix, fewer than two ratings", "non-fix, issue type not rated",
                "non-fix, no linked issue"))
by_status <- do.call(rbind, lapply(seq_len(nrow(groups)), function(j) {
  s <- smsh[smsh$is_bugfix == groups$label[j] & smsh$gt_certainty == groups$certainty[j], ]
  r <- data.frame(group = groups$group[j], commits = nrow(s))
  for (m in pred_cols) r[[sub("isBugfix_", "", m)]] <- round(100 * mean(s[[m]]), 1)
  r
}))
print(by_status)
write.csv(by_status, file.path(OUT_DIR, paste0("P", PROMPT, "_rq3_by_validation_status.csv")), row.names = FALSE)


# 4.2 - errors on disputed commits
disputed <- smsh$gt_certainty == "close"
err <- data.frame(model = sub("isBugfix_", "", pred_cols),
                  errors = sapply(pred_cols, function(m) sum(smsh[[m]] != smsh$is_bugfix)),
                  on_disputed = sapply(pred_cols, function(m) sum(smsh[[m]] != smsh$is_bugfix & disputed)))
err$share <- round(100 * err$on_disputed / err$errors, 1)
cat(sprintf("disputed commits: %d of %d (%.1f%%)\n", sum(disputed), nrow(smsh), 100 * mean(disputed)))
print(err)
write.csv(err, file.path(OUT_DIR, paste0("P", PROMPT, "_rq3_errors_on_disputed.csv")), row.names = FALSE)

# 4.3 - non-fixes by issue type and keyword
cat_tab <- iss %>%
  group_by(repo, hash) %>%
  summarise(linked      = any(issue_key != ""),
            retyped     = any(issue_type == "Bug" & !(issue_type_verified %in% c("bug", "-", ""))),
            bug_report  = any(issue_type == "Bug"),
            feature     = any(issue_type == "New Feature"),
            improvement = any(issue_type == "Improvement"),
            task        = any(issue_type %in% c("Task", "Sub-task", "Technical task")),
            .groups = "drop") %>%
  mutate(category = case_when(!linked     ~ "no linked issue",
                              retyped     ~ "re-typed bug report",
                              bug_report  ~ "bug report, other",
                              feature     ~ "new feature",
                              improvement ~ "improvement",
                              task        ~ "task or sub-task",
                              TRUE        ~ "other issue types"))
nf <- merge(smsh[!smsh$is_bugfix, ], cat_tab[, c("repo", "hash", "category")], by = c("repo", "hash"))
nf$strong_fix <- rowMeans(nf[, strong])
by_issue <- nf %>%
  group_by(category, keyword_fires = isBugfix_stemming) %>%
  summarise(commits = n(), strong_models_fix = round(100 * mean(strong_fix), 1), .groups = "drop")
print(by_issue)
write.csv(by_issue, file.path(OUT_DIR, paste0("P", PROMPT, "_rq3_by_issue_type.csv")), row.names = FALSE)

# 4.4 - commits linked to bug reports
bugfiled <- iss %>% filter(issue_type == "Bug") %>% distinct(repo, hash)
b <- merge(smsh, bugfiled, by = c("repo", "hash"))
retyped <- !b$is_bugfix
cat(sprintf("commits linked to an issue filed as a bug: %d, re-typed by the raters: %d (%.1f%%)\n",
            nrow(b), sum(retyped), 100 * mean(retyped)))
bug_tab <- data.frame(model = sub("isBugfix_", "", pred_cols),
                      called_nonfix = sapply(pred_cols, function(m) sum(!b[[m]])),
                      share_retyped = sapply(pred_cols, function(m) round(100 * sum(!b[[m]] & retyped) / sum(!b[[m]]), 1)),
                      retyped_found = sapply(pred_cols, function(m) round(100 * sum(!b[[m]] & retyped) / sum(retyped), 1)))
print(bug_tab)
write.csv(bug_tab, file.path(OUT_DIR, paste0("P", PROMPT, "_rq3_bug_reports.csv")), row.names = FALSE)


# 5 - heatmaps for both prompts
both <- list("P1, zero-shot" = p1, "P2, few-shot" = p2)
hm <- do.call(rbind, lapply(names(both), function(lab) {
  run <- both[[lab]]
  run <- run[!(run$repo %in% EXCLUDE) & paste(run$repo, run$hash) %in% common & run$dataset == "smartshark", ]
  for (i in 5:ncol(run)) run[, i] <- as.logical(run[, i])
  do.call(rbind, lapply(colnames(run)[6:ncol(run)], function(m) run %>%
    group_by(repo) %>%
    summarise(mcc = mcc(is_bugfix, .data[[m]], cutoff = 0.5), .groups = "drop") %>%
    mutate(predictor = unlist(strsplit(m, "_"))[2], prompt = lab)))
})) %>% mutate(mcc = ifelse(is.nan(mcc), 0, mcc))

ref <- hm %>% filter(prompt == "P2, few-shot")
pred_order_both <- ref %>% group_by(predictor) %>% summarise(m = mean(mcc)) %>% arrange(m) %>% pull(predictor)
repo_order_both <- ref %>% group_by(repo) %>% summarise(m = mean(mcc)) %>% arrange(m) %>% pull(repo)
hm <- hm %>% mutate(predictor = factor(predictor, levels = pred_order_both),
                    repo = factor(repo, levels = repo_order_both))

pC <- ggplot(hm, aes(repo, predictor, fill = mcc)) +
  geom_tile(color = "white", linewidth = 0.3) +
  facet_grid(prompt ~ .) +
  scale_fill_viridis_c(option = "magma", limits = c(min(0, min(hm$mcc)), 1)) +
  scale_y_discrete(labels = display_names) +
  labs(x = NULL, y = NULL, fill = "MCC") +
  theme_minimal(base_size = 7) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
ggsave(file.path(OUT_DIR, "heatmap_mcc_both_prompts.pdf"), pC, width = 5.4, height = 4.6, device = cairo_pdf)

hm_c <- hm %>% group_by(prompt, repo) %>% mutate(mcc_centered = mcc - mean(mcc)) %>% ungroup()
pD <- ggplot(hm_c, aes(repo, predictor, fill = mcc_centered)) +
  geom_tile(color = "white", linewidth = 0.3) +
  facet_grid(prompt ~ .) +
  scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0) +
  scale_y_discrete(labels = display_names) +
  labs(x = NULL, y = NULL, fill = "MCC \u2212 project mean") +
  theme_minimal(base_size = 7) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
ggsave(file.path(OUT_DIR, "heatmap_mcc_centered_both_prompts.pdf"), pD, width = 5.4, height = 4.6, device = cairo_pdf)
