import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "2.1.10"
    kotlin("plugin.serialization") version "2.1.10"
    id("com.gradleup.shadow") version "8.3.5"
    id("application")
}

repositories {
    mavenCentral()
}

kotlin {
    jvmToolchain(23)
}

tasks.shadowJar {
    archiveBaseName.set("shadow")
    mergeServiceFiles()
    manifest {
        attributes["Main-Class"] = "org.anonymous.commitminer.MainKt"
    }
}

application {
    mainClass.set("org.anonymous.commitminer.MainKt")
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        freeCompilerArgs.add("-Xjsr305=strict")
        jvmTarget.set(JvmTarget.JVM_23)
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")
    implementation("com.github.ajalt.clikt:clikt:4.2.1")
    implementation("org.apache.commons:commons-csv:1.12.0")
    implementation("com.londogard:nlp:1.2.0")
    implementation("org.eclipse.jgit:org.eclipse.jgit:6.10.0.202406032230-r")
}
