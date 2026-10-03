package org.anonymous.commitminer

import com.londogard.nlp.stemmer.Stemmer
import com.londogard.nlp.utils.LanguageSupport

/** Method key for the keyword/stemming classifier, written into the out CSV column name. */
const val KEYWORD_CLASSIFIER = "stemming"

/**
 * Message-based bugfix/refactor classifier. Lowercases the commit message, strips non-alphanumerics,
 * stems it, and checks for category keywords. Used by the miner to fill the `isBugfix_stemming`
 * column from the commit message alone (no diff or LOC needed).
 */
class BugfixCommitParser {

    private val stemmer: Stemmer = Stemmer(LanguageSupport.en)
    private val bugFixWordSet = setOf("fix", "bug", "fixup", "fail", "correct")
    private val refactorWordSet = setOf("refactor")

    /** True when the (stemmed) commit message contains a bugfix keyword. */
    fun isBugfix(message: String): Boolean = isCommitOfCategory(message, bugFixWordSet)

    /** True when the (stemmed) commit message contains a refactor keyword. */
    fun isRefactoring(message: String): Boolean = isCommitOfCategory(message, refactorWordSet)

    private fun isCommitOfCategory(message: String, words: Set<String>): Boolean {
        // remove non-alphanumeric chars
        val re = Regex("[^A-Za-z0-9 ]")
        val newMessage = re.replace(message, "").lowercase()

        // stemming
        val stemmedMessage = stemmer.stem(newMessage)
        for (word in words) {
            if (stemmedMessage.contains(word)) {
                return true
            }
        }
        return false
    }
}
