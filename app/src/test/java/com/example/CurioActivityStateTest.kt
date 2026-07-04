package com.example

import com.example.notifications.Attention
import com.example.notifications.CurioActivityState
import com.example.notifications.CurioTask
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure reducer behind Curio's single unified live activity
 * ([CurioActivityState]). No Android deps, so plain JUnit — this is the logic that decides the one
 * notification's headline, progress and dismissal, so it's the part worth pinning down.
 */
class CurioActivityStateTest {

    @Test fun `empty state is empty and shows nothing`() {
        val s = CurioActivityState()
        assertTrue(s.isEmpty)
        assertFalse(s.isOngoing)
        assertNull(s.progress)
        assertEquals("Curio", s.headline)
    }

    @Test fun `a single running task is ongoing with its own label`() {
        val s = CurioActivityState().taskStarted(CurioTask.SYNC)
        assertFalse(s.isEmpty)
        assertTrue(s.isOngoing)
        assertEquals(CurioTask.SYNC.label + "…", s.headline)
    }

    @Test fun `multiple tasks collapse into one 'tidying up' headline`() {
        val s = CurioActivityState()
            .taskStarted(CurioTask.SYNC)
            .taskStarted(CurioTask.INDEX)
        assertEquals("Curio is tidying up…", s.headline)
        // Detail enumerates the concurrent tasks so it still reads as ONE item, not many.
        assertEquals("${CurioTask.SYNC.label} · ${CurioTask.INDEX.label}", s.detail)
    }

    @Test fun `progress averages known task fractions and clamps`() {
        val s = CurioActivityState()
            .taskProgress(CurioTask.INDEX, 25, 100)   // 0.25
            .taskProgress(CurioTask.SWEEP, 75, 100)   // 0.75
        assertEquals(0.5f, s.progress!!, 0.0001f)
    }

    @Test fun `progress is indeterminate until a task reports counts`() {
        val s = CurioActivityState().taskStarted(CurioTask.SWEEP)
        assertNull(s.progress)
    }

    @Test fun `zero total does not divide by zero`() {
        val s = CurioActivityState().taskProgress(CurioTask.INDEX, 0, 0)
        assertTrue(s.activeTasks.contains(CurioTask.INDEX))
        assertNull(s.progress)
    }

    @Test fun `finishing the last task empties the state`() {
        val s = CurioActivityState()
            .taskStarted(CurioTask.SYNC)
            .taskFinished(CurioTask.SYNC)
        assertTrue(s.isEmpty)
    }

    @Test fun `finishing drops that task's progress but keeps the others`() {
        val s = CurioActivityState()
            .taskProgress(CurioTask.INDEX, 50, 100)
            .taskProgress(CurioTask.SWEEP, 10, 100)
            .taskFinished(CurioTask.INDEX)
        assertEquals(setOf(CurioTask.SWEEP), s.activeTasks)
        assertEquals(0.1f, s.progress!!, 0.0001f)
    }

    @Test fun `digest ready is attention, not ongoing, and stays until cleared`() {
        val s = CurioActivityState().withDigestReady(7)
        assertFalse(s.isEmpty)
        assertFalse(s.isOngoing)
        assertEquals("Your weekly digest is ready", s.headline)
        assertEquals("7 saves from the last 7 days", s.detail)
        assertTrue(s.clearedAttention().isEmpty)
    }

    @Test fun `digest ready pluralizes a single save`() {
        assertEquals("1 save from the last 7 days", CurioActivityState().withDigestReady(1).detail)
    }

    @Test fun `error attention surfaces the message and is not ongoing`() {
        val s = CurioActivityState().taskStarted(CurioTask.SYNC).withError("Network down")
        assertFalse(s.isOngoing)  // attention overrides the working headline
        assertEquals("Sync failed", s.headline)
        assertEquals("Network down", s.detail)
    }
}
