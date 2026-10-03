package org.anonymous.commitminer

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ollama generation options serialized alongside each mined prompt, so the execution stage can
 * replay the prompt with the exact decoding settings it was generated for.
 */
@Serializable
data class OllamaOptions(
    val temperature: Double? = null,
    @SerialName("num_ctx")
    val numCtx: Int? = null,
    @SerialName("num_predict")
    val numPredict: Int? = null,
    @SerialName("top_p")
    val topP: Int? = null,
    @SerialName("top_k")
    val topK: Int? = null
)

/**
 * A changed file in a commit. [diff] is an optional (usually truncated) unified-diff snippet; when
 * present it is embedded in the prompt so the model sees the actual change, not just the line counts.
 */
data class FileChangeInfo(
    val filename: String,
    val linesAdded: Int,
    val linesRemoved: Int,
    val diff: String? = null,
)

/**
 * Builds the commit-level bugfix-classification prompt. Pure (no I/O) so prompts can be generated
 * offline and stored, then later executed against any model. When a file carries a
 * [FileChangeInfo.diff] snippet it is included verbatim under that file's entry.
 */
fun buildBugfixDetailedPrompt(
    commitMessage: String,
    totalFiles: Int,
    topFiles: List<FileChangeInfo>,
    withReason: Boolean = false,
): String {
    val fileLines = topFiles.joinToString("\n") { fc ->
        val header = "- ${fc.filename}: +${fc.linesAdded}/-${fc.linesRemoved}"
        if (fc.diff.isNullOrBlank()) header else "$header\n${fc.diff}"
    }
    val formatInstruction = if (withReason)
        """Return JSON only in the shape: {"bugfix": true, "reason": "short reason"} or {"bugfix": false, "reason": "short reason"}"""
    else
        """Return JSON only in the shape: {"bugfix": true} or {"bugfix": false}"""

    return """You are a senior software engineer reviewing one commit. Decide whether the commit is a bug fix.

    A bug fix is a commit whose primary purpose is to repair a defect, meaning behaviour that was supposed to work but did not, such as a crash, a wrong result, a logic error, a regression, or an edge-case failure, among other defects. These examples are illustrative and not exhaustive.
    The change repairs existing intended behaviour rather than adding or changing intended behaviour.

    The following are NOT bug fixes, even when the message contains the word "fix": new features, refactoring, performance work, documentation or comment edits, formatting or style, renaming, configuration changes,
    build or CI changes, dependency updates, version-number bumps, commits that only add or change tests without touching production code, reverts, and merge commits. This list is likewise illustrative and not exhaustive.

    Judge from what the diff does, not from the wording of the message. The word "fix" is not evidence on its own, because it is routinely used for cleanup, tests, builds, and version bumps.
    When the message and the diff disagree, trust the diff. If a commit does several things, call it a bug fix only when repairing a defect is its primary purpose.

    Examples follow. Each shows a message, a short diff, and the answer.

    Message: "Fix crash when config file is missing"
    Diff:
    - ConfigLoader.java: +4/-1
    @@ load(Path p) @@
    -        return Files.readAllLines(p);
    +        if (!Files.exists(p)) {
    +            return Collections.emptyList();
    +        }
    +        return Files.readAllLines(p);
    Answer: {"bugfix": true}

    Message: "v2.4.0"
    Diff:
    - Version.java: +1/-1
    @@ release constants @@
    -    public static final int MINOR = 3;
    +    public static final int MINOR = 4;
    Answer: {"bugfix": false}

    Message: "Correct off-by-one that dropped the last row"
    Diff:
    - Paginator.java: +1/-1
    @@ offset computation @@
    -        int offset = page * size;
    +        int offset = (page - 1) * size;
    Answer: {"bugfix": true}

    Message: "fix flaky timeout in retry test"
    Diff:
    - RetryServiceTest.java: +1/-1
    @@ test setup @@
    -        client.setTimeout(100);
    +        client.setTimeout(2000);
    Answer: {"bugfix": false}

    Message: "fix duplicated validation logic"
    Diff:
    - OrderHandler.java: +1/-6
    @@ handle(Order o) @@
    -        if (o.getId() == null) throw new IllegalArgumentException("id");
    -        if (o.getTotal() < 0) throw new IllegalArgumentException("total");
    +        validate(o);
    Answer: {"bugfix": false}

    Message: "fix build, bump plugin version"
    Diff:
    - pom.xml: +1/-1
    @@ build plugins @@
    -            <version>3.1.0</version>
    +            <version>3.2.1</version>
    Answer: {"bugfix": false}

    Here is the commit to judge: The commit modified a total of $totalFiles files and has the following commit message: "$commitMessage"
    Here is the git diff output of this commit, to decide if this is a bugfix or not:
    $fileLines

    $formatInstruction
    """.trimIndent()
}
