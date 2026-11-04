package com.nolean.no_lean

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DocumentExportCleanupTest {
    private val bytes = "{\"note\":\"বাংলা // ₹100\"}".toByteArray(Charsets.UTF_8)

    @Test fun verifiedExportIsNeverDeleted() {
        val output = ByteArrayOutputStream()
        var deletes = 0
        DocumentBytes.writeAndVerifyOrDelete(bytes, { output },
            { ByteArrayInputStream(output.toByteArray()) }, { deletes++; true })
        assertEquals(0, deletes)
    }

    @Test fun unavailableOutputStillDeletesTheCreatedDocument() {
        var deletes = 0
        val failure = assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerifyOrDelete(bytes, { null },
                { ByteArrayInputStream(bytes) }, { deletes++; true })
        }
        assertEquals("No writable document stream", failure.message)
        assertEquals(1, deletes)
    }

    @Test fun partialWriteClosesBeforeCleanupAndRethrowsTheOriginalFailure() {
        val original = IOException("Provider disconnected")
        var closed = false
        var deletes = 0
        val output = object : ByteArrayOutputStream() {
            override fun write(value: ByteArray, offset: Int, count: Int) {
                super.write(value, offset, minOf(2, count))
                throw original
            }
            override fun close() { closed = true; super.close() }
        }
        val failure = assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerifyOrDelete(bytes, { output },
                { ByteArrayInputStream(bytes) }, {
                    assertTrue(closed)
                    assertEquals(2, output.size())
                    deletes++
                    true
                })
        }
        assertSame(original, failure)
        assertEquals(1, deletes)
    }

    @Test fun failedVerificationDeletesTheIncompleteCopy() {
        var deletes = 0
        assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerifyOrDelete(bytes, { ByteArrayOutputStream() },
                { ByteArrayInputStream(bytes.copyOf(3)) }, { deletes++; true })
        }
        assertEquals(1, deletes)
    }

    @Test fun providerRefusingDeletionDoesNotTurnExportIntoSuccess() {
        val original = IOException("Write refused")
        var deletes = 0
        val failure = assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerifyOrDelete(bytes, { throw original },
                { ByteArrayInputStream(bytes) }, { deletes++; false })
        }
        assertSame(original, failure)
        assertEquals(1, deletes)
    }

    @Test fun deletionExceptionDoesNotHideTheOriginalSaveFailure() {
        val original = IOException("Write refused")
        val failure = assertThrows(IOException::class.java) {
            DocumentBytes.writeAndVerifyOrDelete(bytes, { throw original },
                { ByteArrayInputStream(bytes) }, { throw SecurityException("Deletion refused") })
        }
        assertSame(original, failure)
    }
}
