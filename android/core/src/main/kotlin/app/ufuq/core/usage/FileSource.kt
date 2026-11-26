package app.ufuq.core.usage

import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.Path

/** Small file-reading seam so parsers run on fixtures or in-memory data in tests. */
interface FileSource {
    /**
     * All files under [directory] (recursive) whose name ends in [suffix]. Throws
     * [FileSourceException] if the directory is missing or unreadable.
     */
    fun files(directory: String, suffix: String): List<String>

    fun read(path: String): ByteArray
}

class FileSourceException(message: String) : Exception(message)

/** `~`, `~/x` and `~\x` expand against [home] (default: the `user.home` property, `%USERPROFILE%` on Windows). */
internal fun expandTilde(path: String, home: String = userHome()): String {
    if (path == "~") return home
    if (path.startsWith("~/") || path.startsWith("~\\")) {
        val rest = path.substring(2)
        return if (rest.isEmpty()) home else Path.of(home).resolve(rest).toString()
    }
    return path
}

internal fun userHome(): String = System.getProperty("user.home") ?: ""

/** Real disk access (java.nio, no Android APIs). */
class LocalFileSource(
    /**
     * Files larger than this are read from their tail (whole lines only): the newest data is at the
     * end of an append-only log, and a huge file must not be loaded whole.
     */
    maxFileBytes: Int = 256 * 1024 * 1024,
) : FileSource {
    val maxFileBytes: Int = maxOf(maxFileBytes, 1)

    override fun files(directory: String, suffix: String): List<String> {
        val root = try {
            Path.of(directory)
        } catch (e: Exception) {
            throw FileSourceException("directory not found: $directory")
        }
        if (!Files.isDirectory(root)) throw FileSourceException("directory not found: $directory")
        val result = mutableListOf<String>()
        try {
            Files.walk(root).use { stream ->
                stream.forEach { p ->
                    if (p == root) return@forEach
                    val name = p.fileName?.toString() ?: return@forEach
                    // Skip directories named like a log and dangling symlinks (exists/isDirectory follow links).
                    if (name.endsWith(suffix) && Files.exists(p) && !Files.isDirectory(p)) result += p.toString()
                }
            }
        } catch (e: IOException) {
            throw FileSourceException("directory not readable: $directory")
        } catch (e: java.io.UncheckedIOException) {
            throw FileSourceException("directory not readable: $directory")
        } catch (e: SecurityException) {
            throw FileSourceException("directory not readable: $directory")
        }
        return result.sorted()
    }

    override fun read(path: String): ByteArray {
        try {
            RandomAccessFile(File(path), "r").use { f ->
                val size = f.length()
                val cap = maxFileBytes.toLong()
                if (size <= cap) {
                    val buf = ByteArray(size.toInt())
                    f.readFully(buf)
                    return buf
                }
                f.seek(size - cap)
                val buf = ByteArray(maxFileBytes)
                f.readFully(buf)
                val newline = buf.indexOf(0x0A.toByte())
                return if (newline >= 0) buf.copyOfRange(newline + 1, buf.size) else ByteArray(0)
            }
        } catch (e: IOException) {
            throw FileSourceException("file not readable: $path")
        } catch (e: SecurityException) {
            throw FileSourceException("file not readable: $path")
        } catch (e: OutOfMemoryError) {
            throw FileSourceException("file not readable: $path")
        }
    }
}

/**
 * In-memory files, keyed by full path. A path in [unreadable] throws on read. Directory matching
 * accepts both `/` and `\` as separators, so Windows-style keys work on any OS.
 */
class InMemoryFileSource(
    val files: Map<String, ByteArray> = emptyMap(),
    val unreadable: Set<String> = emptySet(),
) : FileSource {
    companion object {
        fun ofStrings(strings: Map<String, String>, unreadable: Set<String> = emptySet()) =
            InMemoryFileSource(strings.mapValues { it.value.toByteArray(Charsets.UTF_8) }, unreadable)
    }

    private fun isUnder(path: String, directory: String): Boolean {
        if (!path.startsWith(directory)) return false
        if (directory.endsWith("/") || directory.endsWith("\\")) return path.length > directory.length
        return path.length > directory.length && (path[directory.length] == '/' || path[directory.length] == '\\')
    }

    override fun files(directory: String, suffix: String): List<String> {
        val all = files.keys + unreadable
        val matches = all.filter { isUnder(it, directory) && it.endsWith(suffix) }
        // A directory that holds nothing and isn't registered is treated as missing.
        if (matches.isEmpty() && files.keys.none { isUnder(it, directory) }) {
            throw FileSourceException("directory not found: $directory")
        }
        return matches.sorted()
    }

    override fun read(path: String): ByteArray {
        if (path in unreadable) throw FileSourceException("file not readable: $path")
        return files[path] ?: throw FileSourceException("file not found: $path")
    }
}
