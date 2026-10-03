package org.anonymous.commitminer

import kotlinx.serialization.Serializable

/**
 * On-disk format produced by [CommitClassificationPromptMiner]. Holds one ready-to-run LLM prompt
 * per commit so prompt generation (offline, on the git repo) is decoupled from prompt execution
 * (against any model).
 */
@Serializable
data class CommitPromptsFile(
    val withReason: Boolean,
    val prompts: List<CommitPrompt>,
)

@Serializable
data class CommitPrompt(
    val hash: String,
    val prompt: String,
    val options: OllamaOptions,
)
