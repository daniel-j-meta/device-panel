package com.danieljomaa.devicepanel

import android.content.Context
import android.content.Intent
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.percentOffset
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DevicePanelEmulatorTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private lateinit var server: MockWebServer
    private lateinit var dispatcher: StatefulApiDispatcher
    private lateinit var scenario: ActivityScenario<MainActivity>

    @Before
    fun setUp() {
        dispatcher = StatefulApiDispatcher()
        server = MockWebServer().apply {
            this.dispatcher = this@DevicePanelEmulatorTest.dispatcher
            start()
        }
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(MainActivity.EXTRA_LOOPBACK_ONLY, true)
            putExtra(MainActivity.EXTRA_RESET, true)
        }
        scenario = ActivityScenario.launch(intent)
    }

    @After
    fun tearDown() {
        scenario.close()
        server.shutdown()
    }

    @Test
    fun completeControlFlowUsesOnlyLoopbackAndRollsBackFailures() {
        signIn()
        assertState("powerControl", "Off")

        compose.onNodeWithTag("powerControl").performClick()
        waitForServer { it.on }
        assertState("powerControl", "On")

        compose.onNodeWithTag("brightness75").performClick()
        waitForServer { it.brightness == 75 }
        assertState("brightness75", "Selected")

        compose.onNodeWithTag("colorRed").performClick()
        waitForServer { it.colorMode == "red" }
        assertState("colorRed", "Selected")

        compose.onNodeWithTag("temperatureSlider").performTouchInput {
            click(percentOffset(0.25f, 0.5f))
        }
        waitForServer { kotlin.math.abs(it.colorTemperaturePct - 25) <= 3 && it.colorMode == "temperature" }

        dispatcher.failNextCommand()
        compose.onNodeWithTag("powerControl").performClick()
        compose.onNodeWithTag("errorBanner").assertExists()
        assertState("powerControl", "On")

        compose.onNodeWithTag("retryCommand").performClick()
        waitForServer { !it.on }
        assertState("powerControl", "Off")

        dispatcher.updateRoom { it.copy(on = true, brightness = 10, colorTemperaturePct = 80.0) }
        compose.onNodeWithTag("refreshButton").performClick()
        assertState("powerControl", "On")
        assertState("brightness10", "Selected")

        check(dispatcher.paths().isNotEmpty())
        check(dispatcher.paths().all { it.startsWith("/api/v1/") })
    }

    @Test
    fun expiredSessionReturnsToSignIn() {
        signIn()
        dispatcher.expireNextRequest()

        compose.onNodeWithTag("refreshButton").performClick()

        compose.waitUntil(5_000) {
            compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.TestTag, "serverUrlField"))
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Your session has expired. Sign in again.").assertExists()
    }

    private fun signIn() {
        compose.onNodeWithTag("serverUrlField").performTextInput(server.url("/").toString().removeSuffix("/"))
        compose.onNodeWithTag("passwordField").performTextInput("test-pass")
        compose.onNodeWithTag("signInButton").performClick()
        compose.onNodeWithText("Living Room").assertExists()
        compose.onNodeWithTag("connectionStatus").assertExists()
    }

    private fun assertState(tag: String, value: String) {
        compose.waitUntil(5_000) {
            compose.onAllNodes(
                SemanticsMatcher.expectValue(SemanticsProperties.TestTag, tag) and
                    SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value),
            ).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag(tag).assert(
            SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value),
        )
    }

    private fun waitForServer(condition: (StatefulApiDispatcher.Snapshot) -> Boolean) {
        compose.waitUntil(5_000) { condition(dispatcher.snapshot()) }
    }
}
