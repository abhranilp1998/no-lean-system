package com.nolean.no_lean

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentBytesTest {
    private val bytes = "{\"note\":\"বাংলা // ₹100\"}".toByteArray(Charsets.UTF_8)

    @Test fun verifiesExactUnicodeBytesAfterClosingOutput() {
        var closed = false
        val output = object : ByteArrayOutputStream() {
            override fun close() { closed = true; super.close() }
        }
        DocumentBytes.writeAndVerify(bytes, { output }, {
            assertTrue(closed)
            ByteArrayInputStream(output.toByteArray())
        })
        assertArrayEquals(bytes, output.toByteArray())
    }

    @Test fun nullWritableStreamIsFailure() {
        assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerify(bytes, { null }, { ByteArrayInputStream(bytes) })
        }
    }

    @Test fun flushAndCloseFailuresAreNotSuccess() {
        for (failOnFlush in listOf(true, false)) {
            val output = object : ByteArrayOutputStream() {
                override fun flush() { if (failOnFlush) throw IOException("Full") }
                override fun close() { if (!failOnFlush) throw IOException("Disconnected") }
            }
            assertThrows(IOException::class.java) {
                DocumentBytes.writeAndVerify(bytes, { output }, { ByteArrayInputStream(bytes) })
            }
        }
    }

    @Test fun rejectsEmptyTruncatedDifferentAndExtendedReadback() {
        for (saved in listOf(byteArrayOf(), bytes.copyOf(3), bytes.reversedArray(), bytes + byteArrayOf(0))) {
            assertThrows(IOException::class.java) {
                DocumentBytes.writeAndVerify(bytes, { ByteArrayOutputStream() }, { ByteArrayInputStream(saved) })
            }
        }
    }

    @Test fun unreadableDocumentIsFailure() {
        assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerify(bytes, { ByteArrayOutputStream() }, { null })
        }
    }

    @Test fun verifiesLargeExportsAcrossBufferBoundaries() {
        val large = ByteArray(100003) { (it % 251).toByte() }
        DocumentBytes.writeAndVerify(large, { ByteArrayOutputStream() }, { ByteArrayInputStream(large) })
        large[32768] = 42
        assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerify(ByteArray(100003) { (it % 251).toByte() },
                { ByteArrayOutputStream() }, { ByteArrayInputStream(large) })
        }
    }
}
