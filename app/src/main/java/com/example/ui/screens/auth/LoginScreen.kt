package com.example.ui.screens.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Login
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.domain.model.AuthState
import com.example.ui.components.CurioLogoMark
import com.example.ui.theme.GlassTier
import com.example.ui.theme.glassSurface
import com.example.ui.theme.pressBounce
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled

/**
 * High-fidelity, liquid-glass Login Screen supporting OAuth with PKCE.
 */
@Composable
fun LoginScreen(
    state: AuthState,
    tier: GlassTier,
    onLoginClick: () -> Unit,
    errorMessage: String? = null,
    onDismissError: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.inverseOnSurface.copy(alpha = 0.5f)
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .systemBarsPadding()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            // Hero Aesthetic Card
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .glassSurface(
                        tier = tier,
                        shape = CircleShape,
                        tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f),
                        borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
                    ),
                contentAlignment = Alignment.Center
            ) {
                CurioLogoMark(
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(52.dp)
                )
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "CURIO",
                    style = MaterialTheme.typography.displayLarge.copy(
                        fontSize = 52.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = (-4).sp,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                )
                Text(
                    text = "AI RESEARCH BOOKMARK ENGINE",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.ExtraBold,
                        letterSpacing = 1.8.sp
                    )
                )
            }

            // Connection Glass Surface
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .glassSurface(tier = tier)
                    .padding(24.dp)
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "Synchronize & Curate Bookmarks Securely",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.Black,
                            textAlign = TextAlign.Center
                        )
                    )

                    Text(
                        text = "Curio connects securely via official OAuth 2.0 with PKCE and stores credentials encrypted on-device. Screenshot OCR runs on-device; AI summaries, tags and chat are generated by xAI's cloud (Grok) — only the saved post text is sent, and only when you sync or analyze.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                        textAlign = TextAlign.Center
                    )

                    if (errorMessage != null) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .glassSurface(
                                    tier = tier,
                                    shape = RoundedCornerShape(12.dp),
                                    tint = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.35f),
                                    borderColor = MaterialTheme.colorScheme.error.copy(alpha = 0.3f)
                                )
                                .clickable { onDismissError() }
                                .padding(12.dp)
                                .testTag("login_error_banner"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Default.ErrorOutline,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error,
                                modifier = Modifier.size(20.dp)
                            )
                            Text(
                                text = errorMessage,
                                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                                color = MaterialTheme.colorScheme.error,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }

                    val isSigningIn = state is AuthState.SigningIn

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                            .glassSurface(
                                tier = tier,
                                shape = RoundedCornerShape(16.dp),
                                tint = if (isSigningIn) {
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f)
                                } else {
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                                },
                                borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.25f)
                            )
                            .clip(RoundedCornerShape(16.dp))
                            // Give the primary action a single, clear TalkBack label + disabled state.
                            .semantics(mergeDescendants = true) {
                                contentDescription = if (isSigningIn) "Signing in to X" else "Connect with X"
                                if (isSigningIn) disabled()
                            }
                            .pressBounce(enabled = !isSigningIn) { onLoginClick() }
                            .testTag("connect_x_button"),
                        contentAlignment = Alignment.Center
                    ) {
                        if (isSigningIn) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    strokeWidth = 3.dp,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(
                                    text = "SECURE EXCHANGES...",
                                    style = MaterialTheme.typography.labelLarge.copy(
                                        fontWeight = FontWeight.ExtraBold,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                )
                            }
                        } else {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Default.Login,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Text(
                                    text = "CONNECT WITH X",
                                    style = MaterialTheme.typography.labelLarge.copy(
                                        fontWeight = FontWeight.ExtraBold,
                                        color = MaterialTheme.colorScheme.primary,
                                        letterSpacing = 1.sp
                                    )
                                )
                            }
                        }
                    }

                }
            }

            // Trust markers
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(top = 8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Shield,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = "ENCRYPTED · READ-ONLY · YOUR DATA",
                    style = MaterialTheme.typography.labelSmall.copy(
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                        fontWeight = FontWeight.Bold
                    )
                )
            }
        }
    }
}
