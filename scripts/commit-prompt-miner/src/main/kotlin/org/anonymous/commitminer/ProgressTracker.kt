package org.anonymous.commitminer

class ProgressTracker(private val total: Int, private val label: String = "Item") {
    private var processed = 0
    private val startTime = System.currentTimeMillis()

    fun tick() {
        processed++
        if (processed > 1) {
            val elapsedMs = System.currentTimeMillis() - startTime
            val estimatedTotalMs = ((elapsedMs.toDouble() / (processed - 1)) * total).toLong()
            println("$label $processed / $total | ${formatDuration(elapsedMs)}/${formatDuration(estimatedTotalMs)}")
        }
    }
}

internal fun formatDuration(durationMs: Long): String {
    val totalSeconds = durationMs / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%02d:%02d".format(minutes, seconds)
}
