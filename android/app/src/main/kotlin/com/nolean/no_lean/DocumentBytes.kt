package com.nolean.no_lean

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/** Success means the provider closed the write and returned exactly the same bytes. */
internal object DocumentBytes {
    /** SAF has already created a new document. A failed copy is removed best-effort. */
    fun writeAndVerifyOrDelete(
        bytes: ByteArray,
        openOutput: () -> OutputStream?,
        openInput: () -> InputStream?,
        deleteDocument: () -> Boolean,
    ) {
        try {
            writeAndVerify(bytes, openOutput, openInput)
        } catch (failure: Exception) {
            try {
                deleteDocument()
            } catch (_: Exception) {
                // Some providers reject deletion. Keep the original save failure.
            }
            throw failure
        }
    }

    fun writeAndVerify(
        bytes: ByteArray,
        openOutput: () -> OutputStream?,
        openInput: () -> InputStream?,
    ) {
        val output = openOutput() ?: throw IOException("No writable document stream")
        output.use {
            it.write(bytes)
            it.flush()
        }
        val input = openInput() ?: throw IOException("Cannot verify the saved document")
        input.use {
            val buffer = ByteArray(32768)
            var offset = 0
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                if (count == 0) throw IOException("Document stream stopped responding")
                if (offset + count > bytes.size) throw IOException("Saved document has extra bytes")
                for (index in 0 until count) {
                    if (buffer[index] != bytes[offset + index]) {
                        throw IOException("Saved document differs from the export")
                    }
                }
                offset += count
            }
            if (offset != bytes.size) throw IOException("Saved document is incomplete")
        }
    }
}
