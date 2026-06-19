package com.example

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.example.domain.model.AuthState
import com.example.ui.screens.auth.LoginScreen
import com.example.ui.theme.GlassTier
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Compose smoke test: the login screen renders and the connect button emits its click. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h800dp")
class LoginScreenSmokeTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun `connect button renders and emits click`() {
        var clicked = false
        composeRule.setContent {
            LoginScreen(
                state = AuthState.SignedOut,
                tier = GlassTier.Solid,
                onLoginClick = { clicked = true }
            )
        }

        composeRule.onNodeWithTag("connect_x_button").assertIsDisplayed()
        composeRule.onNodeWithTag("connect_x_button").performClick()
        assertTrue("onLoginClick should fire", clicked)
    }
}
