package com.danieljomaa.devicepanel

import com.danieljomaa.devicepanel.data.RoomChanges
import com.danieljomaa.devicepanel.data.RoomColorMode
import com.danieljomaa.devicepanel.data.RoomState
import com.danieljomaa.devicepanel.data.applying
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RoomModelTest {
    @Test
    fun decodesSharedRoomFixtureShape() {
        val state = Json.decodeFromString<RoomState>(
            """{"on":true,"brightness":34,"colorTemperaturePct":50,"colorMode":"temperature","observedAt":"2026-10-08T12:00:00.123Z","stateSource":"representative"}""",
        )

        assertEquals(34, state.brightness)
        assertEquals(RoomColorMode.TEMPERATURE, state.colorMode)
    }

    @Test
    fun rejectsInvalidBrightness() {
        assertThrows(IllegalArgumentException::class.java) {
            RoomState(true, 0, 50.0, RoomColorMode.TEMPERATURE, "now", "representative")
        }
    }

    @Test
    fun temperatureChangeRestoresTemperatureMode() {
        val red = RoomState(true, 75, 50.0, RoomColorMode.RED, "now", "representative")
        assertEquals(RoomColorMode.TEMPERATURE, red.applying(RoomChanges(colorTemperaturePct = 25.0)).colorMode)
    }
}
