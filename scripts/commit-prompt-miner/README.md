# Commit prompt miner

The miner reads a Git repository and writes two files for every commit. `<repo>-bugfixes.csv` contains the commit hash, the message and the verdict of the keyword baseline (`isBugfix_stemming`). `<repo>-commit-prompts.json` contains one ready-to-run prompt per commit. The miner makes no network or model calls.

Build and run it with the Gradle wrapper, which provisions a JDK 23 if needed.

```bash
./gradlew shadowJar
java -jar build/libs/shadow-*.jar -r <repo> -o <out-dir> [options]
```

The options and the settings used in the study are described in the README at the top of the repository.
