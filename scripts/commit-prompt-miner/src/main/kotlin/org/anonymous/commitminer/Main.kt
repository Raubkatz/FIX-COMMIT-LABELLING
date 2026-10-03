package org.anonymous.commitminer

/** Entry point: the miner is the root command, so options are passed directly (no subcommand name). */
fun main(args: Array<String>) = CommitClassificationPromptMiner().main(args)
