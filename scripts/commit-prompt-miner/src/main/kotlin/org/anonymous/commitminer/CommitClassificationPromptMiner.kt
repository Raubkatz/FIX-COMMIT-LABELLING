package org.anonymous.commitminer

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.parameters.options.check
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.options.required
import com.github.ajalt.clikt.parameters.types.file
import com.github.ajalt.clikt.parameters.types.int
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.apache.commons.csv.CSVFormat
import org.apache.commons.csv.CSVPrinter
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.diff.DiffEntry
import org.eclipse.jgit.diff.DiffFormatter
import org.eclipse.jgit.diff.RawTextComparator
import org.eclipse.jgit.internal.storage.file.FileRepository
import org.eclipse.jgit.revwalk.RevWalk
import org.eclipse.jgit.treewalk.CanonicalTreeParser
import org.eclipse.jgit.treewalk.EmptyTreeIterator
import org.eclipse.jgit.treewalk.AbstractTreeIterator
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Generates the offline first half of the commit-bugfix-classification pipeline. It works directly
 * on a git repository (no intermediate JSON/CSV inputs, no filtering) and makes no LLM calls. It
 * writes two files into `--out-dir`:
 *  - `<repo>-bugfixes.csv` — the "out" CSV with the keyword (stemming) classifier already filled in.
 *  - `<repo>-commit-prompts.json` — one ready-to-run LLM prompt per commit.
 *
 * The prompts JSON can later be executed against a chosen model and folded back into the CSV.
 */
class CommitClassificationPromptMiner(
    name: String = "CommitClassificationPromptMiner",
    help: String = "Generate per-commit bugfix-classification prompts directly from a git repo",
) : CliktCommand(name = name, help = help) {

    private val repository by option("--repository", "-r", help = "Git repository directory")
        .file(mustExist = true, canBeDir = true, canBeFile = false)
        .required()
        .check("Not a git repository (and no .git directory found inside it)") {
            isGitRepository(it) || isGitRepository(File(it, ".git"))
        }

    private val outDir by option("--out-dir", "-o", help = "Output directory for the CSV and prompts JSON")
        .file(mustExist = false, canBeDir = true, canBeFile = false)
        .required()

    private val topNFiles by option("--top-files", "-n")
        .int()
        .default(10)

    private val maxDiffLines by option(
        "--max-diff-lines", "-l",
        help = "Max diff lines included per file in the prompt (0 disables diffs, keeping only the +/- summary)"
    ).int().default(15)

    private val withReason by option("--with-reason", help = "Generate prompts that ask for a short reason")
        .flag(default = false)

    private val hashesFile by option(
        "--hashes",
        help = "Path to a .txt file with one commit hash per line; only those commits are mined"
    ).file(mustExist = true, canBeDir = false, canBeFile = true)

    private val json = Json { prettyPrint = true; encodeDefaults = true }

    /** The git directory to parse: the passed dir itself, or its `.git` subdir for a working tree. */
    private val gitDir: File
        get() = if (isGitRepository(repository)) repository else File(repository, ".git")

    /** Friendly project name for output file prefixes: the working-tree dir, not a literal `.git`. */
    private val projectName: String
        get() {
            val workTree = if (repository.name == ".git") repository.canonicalFile.parentFile
            else repository.canonicalFile
            return (workTree?.name ?: "repo").removeSuffix(".git")
        }

    override fun run() {
        outDir.mkdirs()

        println("Reading git repository ${gitDir.path} ...")
        // Message-only classifier: no lines-of-code parsing needed.
        val classifier = BugfixCommitParser()

        // Larger context window when diffs are embedded, since they make the prompt much longer.
        val options = OllamaOptions(
            temperature = 0.0,
            numCtx = if (maxDiffLines > 0) 4096 else 1024,
            numPredict = if (withReason) 64 else 8,
            topP = 0,
            topK = 1,
        )

        val csvRows = mutableListOf<CommitRow>()
        val prompts = mutableListOf<CommitPrompt>()

        RepoReader(gitDir).use { repo ->
            // Cheap pass: just hash + message per commit (no file contents, no LOC, no diffs yet).
            val commits = repo.listCommits()
                .sortedBy { it.timeSeconds }
                .let { all ->
                    val wanted = readHashes() ?: return@let all
                    val filtered = all.filter { c -> wanted.any { c.hash == it || c.hash.startsWith(it) } }
                    val missing = wanted.filter { w -> all.none { c -> c.hash == w || c.hash.startsWith(w) } }
                    if (missing.isNotEmpty()) {
                        System.err.println("WARNING: ${missing.size} hash(es) from ${hashesFile?.name} not found: ${missing.joinToString(", ")}")
                    }
                    println("Filtering to ${filtered.size} commit(s) from ${hashesFile?.name}")
                    filtered
                }

            val tracker = ProgressTracker(commits.size, "Commits")
            commits.forEach { c ->
                tracker.tick()
                csvRows += CommitRow(c.hash, c.message, classifier.isBugfix(c.message))

                // Diffs are pulled lazily, per commit, only for the commits we actually emit.
                val changedFiles = repo.changedFiles(c.hash)
                val topFiles = changedFiles
                    .sortedByDescending { it.added + it.removed }
                    .take(topNFiles)
                    .map { f ->
                        FileChangeInfo(
                            filename = f.path.substringAfterLast('/'),
                            linesAdded = f.added,
                            linesRemoved = f.removed,
                            diff = if (maxDiffLines > 0) truncateDiff(repo.renderDiff(f.entry), maxDiffLines) else null,
                        )
                    }

                prompts += CommitPrompt(
                    hash = c.hash,
                    prompt = buildBugfixDetailedPrompt(
                        commitMessage = c.message,
                        totalFiles = changedFiles.size,
                        topFiles = topFiles,
                        withReason = withReason,
                    ),
                    options = options,
                )
            }
        }

        writeCsv(File(outDir, "$projectName-bugfixes.csv"), csvRows)

        val promptsFile = File(outDir, "$projectName-commit-prompts.json")
        promptsFile.writeText(json.encodeToString(CommitPromptsFile(withReason, prompts)))

        println("Wrote ${prompts.size} prompt(s) to ${promptsFile.path}")
        println("Done.")
    }

    private fun writeCsv(outputFile: File, rows: List<CommitRow>) {
        val headers = listOf("hash", "message", "isBugfix_$KEYWORD_CLASSIFIER")

        val tmpFile = File(outDir, "${outputFile.nameWithoutExtension}.csv.tmp")
        CSVPrinter(
            tmpFile.bufferedWriter(),
            CSVFormat.DEFAULT.builder().setHeader(*headers.toTypedArray()).build()
        ).use { printer ->
            rows.forEach { printer.printRecord(it.hash, it.message, it.isBugfix.toString()) }
        }

        Files.move(
            tmpFile.toPath(), outputFile.toPath(),
            StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE
        )
        println("Wrote ${rows.size} commit(s) to ${outputFile.path}")
    }

    /** Reads the commit hashes to restrict mining to, from [hashesFile] (one hash per line). */
    private fun readHashes(): Set<String>? {
        val file = hashesFile ?: return null
        return file.readLines()
            .map { it.substringBefore('#').trim() }
            .filter { it.isNotEmpty() }
            .toSet()
    }

    /**
     * Keeps at most [maxLines] lines of the hunk body of [diff], dropping the git file header
     * (`diff --git`/`index`/`---`/`+++`) so the budget is spent on actual changed lines. Appends a
     * truncation marker when lines were dropped.
     */
    private fun truncateDiff(diff: String, maxLines: Int): String {
        if (diff.isBlank() || maxLines <= 0) return ""
        val body = diff.lineSequence().dropWhile { !it.startsWith("@@") }.toList()
            .ifEmpty { diff.lines() }
        val kept = body.take(maxLines)
        val suffix = if (body.size > maxLines) "\n... (diff truncated)" else ""
        return kept.joinToString("\n") + suffix
    }
}

/** One output CSV row: commit hash, message and the keyword (stemming) bugfix verdict. */
private data class CommitRow(val hash: String, val message: String, val isBugfix: Boolean)

/**
 * Lightweight git reader used straight against the object database (no working tree needed):
 *  - [listCommits] returns just hash + message + merge flag + time (cheap, no file I/O).
 *  - [changedFiles] returns a commit's changed files with +/- counts (vs. its first parent).
 *  - [renderDiff] formats the unified diff for one file on demand.
 */
private class RepoReader(gitDir: File) : AutoCloseable {
    private val repository = FileRepository(gitDir)
    private val git = Git(repository)
    private val revWalk = RevWalk(repository)
    private val reader = repository.newObjectReader()
    private val out = ByteArrayOutputStream()
    private val formatter = DiffFormatter(out).also {
        it.setRepository(repository)
        it.setDiffComparator(RawTextComparator.DEFAULT)
        it.isDetectRenames = true
    }

    data class CommitMeta(val hash: String, val message: String, val isMerge: Boolean, val timeSeconds: Long)
    class ChangedFile(val path: String, val added: Int, val removed: Int, val entry: DiffEntry)

    /** All commits reachable from HEAD — hash + message only, no diffs or file contents. */
    fun listCommits(): List<CommitMeta> = git.log().call().map { c ->
        CommitMeta(
            hash = c.name,
            message = c.shortMessage,
            isMerge = c.parentCount > 1,
            timeSeconds = c.authorIdent.getWhen().toInstant().epochSecond,
        )
    }

    /** Changed files for a commit (vs. its first parent) with +/- line counts. Diff text via [renderDiff]. */
    fun changedFiles(hash: String): List<ChangedFile> {
        val objectId = repository.resolve(hash) ?: return emptyList()
        val commit = revWalk.parseCommit(objectId)

        val newTree = CanonicalTreeParser().also { it.reset(reader, commit.tree) }
        val oldTree: AbstractTreeIterator = if (commit.parentCount > 0) {
            val parent = revWalk.parseCommit(commit.getParent(0).id)
            CanonicalTreeParser().also { it.reset(reader, parent.tree) }
        } else {
            EmptyTreeIterator()
        }

        return formatter.scan(oldTree, newTree).map { entry ->
            var added = 0
            var removed = 0
            formatter.toFileHeader(entry).toEditList().forEach { e ->
                added += e.endB - e.beginB
                removed += e.endA - e.beginA
            }
            val path = if (entry.newPath == DiffEntry.DEV_NULL) entry.oldPath else entry.newPath
            ChangedFile(path, added, removed, entry)
        }
    }

    /** Unified diff text for a single changed file. */
    fun renderDiff(entry: DiffEntry): String {
        out.reset()
        formatter.format(entry)
        formatter.flush()
        return out.toString(StandardCharsets.UTF_8)
    }

    override fun close() {
        formatter.close()
        reader.close()
        revWalk.close()
        git.close()
        repository.close()
    }
}
