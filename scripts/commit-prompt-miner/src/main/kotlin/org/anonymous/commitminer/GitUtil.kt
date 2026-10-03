package org.anonymous.commitminer

import org.eclipse.jgit.lib.RepositoryCache
import org.eclipse.jgit.util.FS
import java.io.File

/** True when [directory] is (or directly contains) a git repository. */
fun isGitRepository(directory: File): Boolean =
    RepositoryCache.FileKey.isGitRepository(directory, FS.DETECTED)
