package com.example.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Dataset
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Label
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.RocketLaunch
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.Workspaces
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.domain.model.RuleField
import com.example.domain.model.RuleMatch
import com.example.domain.model.RuleOp
import com.example.domain.model.Space
import com.example.domain.model.SpaceRule
import com.example.domain.model.SpaceRules
import com.example.ui.theme.GlassTier
import com.example.ui.theme.bounceScale
import com.example.ui.theme.glassSurface
import com.example.ui.theme.pressBounce
import com.example.ui.theme.CurioColors

/** The curated set of icons a Space can use, keyed by a stable string persisted on the entity. */
internal val spaceIconKeys: List<String> =
    listOf(
        "workspaces", "folder", "star", "science", "code", "book", "lightbulb", "rocket",
        "favorite", "label", "hub", "bolt", "psychology", "dataset", "school", "terminal",
        "image", "public", "flag", "bug", "bookmark"
    )

/** Resolves a persisted [iconKey] to its Material icon, defaulting to the generic Workspaces glyph. */
internal fun spaceIcon(iconKey: String?): ImageVector = when (iconKey) {
    "folder" -> Icons.Filled.Folder
    "star" -> Icons.Filled.Star
    "science" -> Icons.Filled.Science
    "code" -> Icons.Filled.Code
    "book" -> Icons.AutoMirrored.Filled.MenuBook
    "lightbulb" -> Icons.Filled.Lightbulb
    "rocket" -> Icons.Filled.RocketLaunch
    "favorite" -> Icons.Filled.Favorite
    "label" -> Icons.Filled.Label
    "hub" -> Icons.Filled.Hub
    "bolt" -> Icons.Filled.Bolt
    "psychology" -> Icons.Filled.Psychology
    "dataset" -> Icons.Filled.Dataset
    "school" -> Icons.Filled.School
    "terminal" -> Icons.Filled.Terminal
    "image" -> Icons.Filled.Image
    "public" -> Icons.Filled.Public
    "flag" -> Icons.Filled.Flag
    "bug" -> Icons.Filled.BugReport
    "bookmark" -> Icons.Filled.Bookmarks
    else -> Icons.Filled.Workspaces
}

/** Palette offered in the Space editor; values are packed ARGB longs stored on the entity. */
internal val spacePalette: List<Long> = listOf(
    0xFF1E88E5, 0xFF43A047, 0xFF8E24AA, 0xFF00BCD4, 0xFFFF9800,
    0xFFE91E63, 0xFF3F51B5, 0xFF009688, 0xFFFFC107, 0xFFFF5722,
    0xFF673AB7, 0xFF607D8B, 0xFF2196F3, 0xFF4CAF50, 0xFFFF4081,
    0xFF795548, 0xFF00E5FF, 0xFFCDDC39
)

/**
 * Spaces home — the user's library organised into named collections. Lives where Insights used to
 * sit in the bottom navigation; Insights moved to the side drawer. Tapping a Space opens the feed
 * scoped to that collection ([onOpenSpace]).
 */
@Composable
internal fun CurioSpacesScreen(
    viewModel: BookmarkViewModel,
    tier: GlassTier,
    onOpenSpace: (Space) -> Unit
) {
    val spaces by viewModel.spaces.collectAsStateWithLifecycle()
    val stats by viewModel.stats.collectAsStateWithLifecycle()

    var editorTarget by remember { mutableStateOf<Space?>(null) }
    var showCreate by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<Space?>(null) }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(top = 4.dp)) {
                    Text(
                        text = "ORGANIZE YOUR INDEX",
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = 1.2.sp),
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        text = "Group bookmarks into Spaces — collections you control, separate from AI categories.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }
            }

            // Create-new-space tile — hidden when empty (empty state has its own CTA).
            if (spaces.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassSurface(tier = tier, shape = RoundedCornerShape(18.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.3f))
                        .pressBounce { showCreate = true }
                        .padding(horizontal = 16.dp, vertical = 16.dp)
                        .testTag("create_space_button"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    }
                    Column {
                        Text("New Space", style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.onSurface)
                        Text("Create a collection", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                    }
                }
            }
            }

            if (spaces.isEmpty()) {
                item { SpacesEmptyState(tier = tier, onCreate = { showCreate = true }) }
            } else {
                items(spaces, key = { it.id }) { space ->
                    SpaceCard(
                        space = space,
                        totalCount = stats.totalCount,
                        tier = tier,
                        onOpen = { onOpenSpace(space) },
                        onEdit = { editorTarget = space },
                        onDelete = { pendingDelete = space },
                        onTogglePin = { viewModel.setSpacePinned(space.id, !space.isPinned) },
                        onApplyRules = { viewModel.applySpaceRules(space) }
                    )
                }
            }

            item { Spacer(modifier = Modifier.height(80.dp)) }
        }
    }

    if (showCreate) {
        SpaceEditorDialog(
            existing = null,
            tier = tier,
            onDismiss = { showCreate = false },
            onConfirm = { name, color, icon, description, rules, isPinned ->
                viewModel.createSpace(name, color, icon, description, rules, isPinned)
                showCreate = false
            }
        )
    }

    editorTarget?.let { target ->
        SpaceEditorDialog(
            existing = target,
            tier = tier,
            onDismiss = { editorTarget = null },
            onConfirm = { name, color, icon, description, rules, isPinned ->
                viewModel.updateSpace(target.id, name, color, icon, description, rules, isPinned)
                editorTarget = null
            }
        )
    }

    pendingDelete?.let { target ->
        DeleteSpaceDialog(
            space = target,
            tier = tier,
            onDismiss = { pendingDelete = null },
            onConfirm = {
                viewModel.deleteSpace(target.id)
                pendingDelete = null
            }
        )
    }
}

@Composable
private fun SpaceCard(
    space: Space,
    totalCount: Int,
    tier: GlassTier,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onTogglePin: () -> Unit,
    onApplyRules: () -> Unit
) {
    val color = Color(space.color)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .glassSurface(tier = tier, shape = RoundedCornerShape(20.dp), tint = color.copy(alpha = 0.08f))
            .pressBounce(onClick = onOpen)
            .padding(start = 14.dp, end = 8.dp, top = 14.dp, bottom = 14.dp)
            .testTag("space_card_${space.id}")
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .background(Brush.linearGradient(listOf(color.copy(alpha = 0.95f), color.copy(alpha = 0.5f))), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(spaceIcon(space.icon), contentDescription = null, tint = CurioColors.onColor(color), modifier = Modifier.size(24.dp))
                }
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = space.name,
                            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black),
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false)
                        )
                        if (space.isPinned) {
                            Icon(Icons.Filled.PushPin, contentDescription = "Pinned", tint = color, modifier = Modifier.size(14.dp))
                        }
                        if (space.isSmart) SmartBadge(color)
                    }
                    Text(
                        text = buildString {
                            append("${space.count} ")
                            append(if (space.count == 1) "bookmark" else "bookmarks")
                            if (totalCount > 0) append(" · ${(space.count * 100) / totalCount.coerceAtLeast(1)}% of index")
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                    )
                }
                // Keep the frequent Pin toggle inline; fold Apply/Edit/Delete into a single overflow
                // menu so the row isn't a cluster of 4 tap targets fighting the whole-card open gesture.
                SpaceIconButton(
                    if (space.isPinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                    if (space.isPinned) "Unpin ${space.name}" else "Pin ${space.name}",
                    if (space.isPinned) color else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f),
                    onTogglePin
                )
                Box {
                    var menuExpanded by remember { mutableStateOf(false) }
                    SpaceIconButton(
                        Icons.Default.MoreVert,
                        "More actions for ${space.name}",
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                    ) { menuExpanded = true }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        if (space.isSmart) {
                            DropdownMenuItem(
                                text = { Text("Apply rules") },
                                leadingIcon = { Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = color) },
                                onClick = { menuExpanded = false; onApplyRules() }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("Edit") },
                            leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) },
                            onClick = { menuExpanded = false; onEdit() }
                        )
                        DropdownMenuItem(
                            text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                            onClick = { menuExpanded = false; onDelete() }
                        )
                    }
                }
            }

            if (space.description.isNotBlank()) {
                Text(
                    text = space.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(start = 2.dp)
                )
            }
        }
    }
}

/** Small "SMART" pill marking a rule-driven Space. */
@Composable
private fun SmartBadge(color: Color) {
    Row(
        modifier = Modifier
            .background(color.copy(alpha = 0.16f), RoundedCornerShape(6.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = color, modifier = Modifier.size(10.dp))
        Text("SMART", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontSize = 8.sp, letterSpacing = 0.5.sp), color = color)
    }
}

@Composable
private fun SpaceIconButton(icon: ImageVector, contentDescription: String, tint: Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(48.dp)
            .pressBounce(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = contentDescription, tint = tint, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun SpacesEmptyState(tier: GlassTier, onCreate: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 24.dp)
            .glassSurface(tier = tier, shape = RoundedCornerShape(28.dp), tint = MaterialTheme.colorScheme.surface.copy(alpha = 0.4f))
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Filled.Workspaces, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(34.dp))
        }
        Text("NO SPACES YET", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = 1.sp), color = MaterialTheme.colorScheme.onSurface)
        Text(
            "Create your first Space to start grouping bookmarks — like \"To Read\", \"Diffusion\", or \"Thesis\".",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
        Box(
            modifier = Modifier
                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(16.dp))
                .pressBounce(onClick = onCreate)
                .padding(horizontal = 24.dp, vertical = 12.dp),
            contentAlignment = Alignment.Center
        ) {
            Text("CREATE A SPACE", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onPrimary))
        }
    }
}

/**
 * Create-or-edit dialog for a Space. Supplies a name field, an optional description, a color and
 * icon picker, a "pin to top" toggle, and a Smart-Space rule builder. Reused for both creation
 * (existing == null) and editing.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SpaceEditorDialog(
    existing: Space?,
    tier: GlassTier,
    onDismiss: () -> Unit,
    onConfirm: (name: String, color: Long, icon: String, description: String, rules: SpaceRules, isPinned: Boolean) -> Unit
) {
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var color by remember { mutableStateOf(existing?.color ?: spacePalette.first()) }
    var icon by remember { mutableStateOf(existing?.icon ?: spaceIconKeys.first()) }
    var isPinned by remember { mutableStateOf(existing?.isPinned ?: false) }

    // Rule-builder state, seeded from the existing Space's rules (if any).
    val rules = remember { mutableStateListOf<SpaceRule>().apply { existing?.rules?.rules?.let { addAll(it) } } }
    var matchMode by remember { mutableStateOf(existing?.rules?.match ?: RuleMatch.ANY) }
    var autoFile by remember { mutableStateOf(existing?.rules?.autoFile ?: true) }

    fun assembledRules() = SpaceRules(match = matchMode, autoFile = autoFile, rules = rules.toList())

    SlideUpCard(
        onDismissRequest = onDismiss,
        tier = tier,
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
                val dismiss = LocalSlideUpDismiss.current
                Text(
                    text = if (existing == null) "NEW SPACE" else "EDIT SPACE",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary, letterSpacing = 1.sp)
                )

                androidx.compose.material3.OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    placeholder = { Text("Space name") },
                    modifier = Modifier.fillMaxWidth().testTag("space_name_input"),
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color(color),
                        unfocusedBorderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f)
                    ),
                    shape = RoundedCornerShape(12.dp)
                )

                androidx.compose.material3.OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    singleLine = true,
                    placeholder = { Text("Description (optional)") },
                    modifier = Modifier.fillMaxWidth().testTag("space_description_input"),
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color(color),
                        unfocusedBorderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f)
                    ),
                    shape = RoundedCornerShape(12.dp)
                )

                // Pin-to-top toggle
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f), RoundedCornerShape(12.dp))
                        .pressBounce { isPinned = !isPinned }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        if (isPinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                        contentDescription = null,
                        tint = if (isPinned) Color(color) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                        modifier = Modifier.size(18.dp)
                    )
                    Text("Pin to top", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                    Switch(
                        checked = isPinned,
                        onCheckedChange = { isPinned = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = Color(color)),
                        modifier = Modifier.testTag("space_pin_switch")
                    )
                }

                // Color picker
                Text("COLOR", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                androidx.compose.foundation.layout.FlowRow(
                    modifier = Modifier.fillMaxWidth().selectableGroup(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    spacePalette.forEachIndexed { i, c ->
                        val selected = c == color
                        Box(
                            modifier = Modifier
                                .size(34.dp)
                                .bounceScale(selected)
                                .background(Color(c), CircleShape)
                                .border(width = if (selected) 3.dp else 0.dp, color = MaterialTheme.colorScheme.onSurface, shape = CircleShape)
                                // Radio semantics so TalkBack announces "Color N, radio button, selected".
                                .selectable(
                                    selected = selected,
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                    role = Role.RadioButton,
                                    onClick = { color = c }
                                )
                                .semantics { contentDescription = "Color ${i + 1}" },
                            contentAlignment = Alignment.Center
                        ) {
                            if (selected) Icon(Icons.Default.Check, contentDescription = null, tint = CurioColors.onColor(Color(c)), modifier = Modifier.size(18.dp))
                        }
                    }
                }

                // Icon picker
                Text("ICON", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                androidx.compose.foundation.layout.FlowRow(
                    modifier = Modifier.fillMaxWidth().selectableGroup(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    spaceIconKeys.forEach { key ->
                        val selected = key == icon
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .bounceScale(selected)
                                .background(if (selected) Color(color).copy(alpha = 0.2f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f), RoundedCornerShape(10.dp))
                                .border(width = 1.dp, color = if (selected) Color(color) else Color.Transparent, shape = RoundedCornerShape(10.dp))
                                // The child Icon's contentDescription (= key) supplies the label.
                                .selectable(
                                    selected = selected,
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                    role = Role.RadioButton,
                                    onClick = { icon = key }
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(spaceIcon(key), contentDescription = key, tint = if (selected) Color(color) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), modifier = Modifier.size(20.dp))
                        }
                    }
                }

                // ── Smart-Space rule builder ──────────────────────────────────
                SpaceRulesEditor(
                    accent = Color(color),
                    rules = rules,
                    matchMode = matchMode,
                    autoFile = autoFile,
                    onMatchModeChange = { matchMode = it },
                    onAutoFileChange = { autoFile = it }
                )

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f), RoundedCornerShape(14.dp))
                            .pressBounce { dismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Text("CANCEL", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)))
                    }
                    val canSave = name.isNotBlank()
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(if (canSave) Color(color) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f), RoundedCornerShape(14.dp))
                            .pressBounce(enabled = canSave) { onConfirm(name, color, icon, description, assembledRules(), isPinned) }
                            .testTag("space_save_button"),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(if (existing == null) "CREATE" else "SAVE", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, color = if (canSave) CurioColors.onColor(Color(color)) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)))
                    }
                }
    }
}

/**
 * The Smart-Space rule editor. Each rule is "[field] [op] [value]"; field/op are cycled by tapping
 * their pill (a deliberately dropdown-free design that stays reliable inside a bottom sheet). When
 * at least one rule exists, an ANY/ALL match toggle and an "auto-file" switch appear.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SpaceRulesEditor(
    accent: Color,
    rules: androidx.compose.runtime.snapshots.SnapshotStateList<SpaceRule>,
    matchMode: RuleMatch,
    autoFile: Boolean,
    onMatchModeChange: (RuleMatch) -> Unit,
    onAutoFileChange: (Boolean) -> Unit
) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = accent, modifier = Modifier.size(14.dp))
            Text("SMART RULES", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = onSurface.copy(alpha = 0.6f))
        }
        Text(
            "Auto-file bookmarks that match these conditions.",
            style = MaterialTheme.typography.labelSmall,
            color = onSurface.copy(alpha = 0.45f)
        )

        rules.forEachIndexed { index, rule ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(onSurface.copy(alpha = 0.04f), RoundedCornerShape(12.dp))
                    .padding(10.dp)
                    .testTag("space_rule_$index"),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    RuleFieldDropdown(
                        text = rule.field.label,
                        accent = accent,
                        modifier = Modifier.testTag("space_rule_field_$index")
                    ) { field ->
                        rules[index] = rule.copy(field = field)
                    }
                    RuleOpDropdown(text = rule.op.label, accent = accent) { op ->
                        rules[index] = rule.copy(op = op)
                    }
                    Box(modifier = Modifier.weight(1f))
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = "Remove rule",
                        tint = MaterialTheme.colorScheme.error.copy(alpha = 0.8f),
                        modifier = Modifier
                            .size(20.dp)
                            .clip(CircleShape)
                            .pressBounce { rules.removeAt(index) }
                            .padding(2.dp)
                    )
                }
                androidx.compose.material3.OutlinedTextField(
                    value = rule.value,
                    onValueChange = { rules[index] = rule.copy(value = it) },
                    singleLine = true,
                    placeholder = { Text(rulePlaceholder(rule.field)) },
                    modifier = Modifier.fillMaxWidth().testTag("space_rule_value_$index"),
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = accent,
                        unfocusedBorderColor = onSurface.copy(alpha = 0.15f)
                    ),
                    shape = RoundedCornerShape(10.dp)
                )
            }
        }

        // Add-rule button.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(accent.copy(alpha = 0.10f), RoundedCornerShape(12.dp))
                .pressBounce { rules.add(SpaceRule(RuleField.KEYWORD, RuleOp.CONTAINS, "")) }
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .testTag("space_add_rule_button"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(Icons.Default.Add, contentDescription = null, tint = accent, modifier = Modifier.size(16.dp))
            Text(
                if (rules.isEmpty()) "Add a rule" else "Add another rule",
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                color = accent
            )
        }

        // Match-mode + auto-file controls only matter once a rule exists.
        if (rules.isNotEmpty()) {
            if (rules.size > 1) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Match", style = MaterialTheme.typography.bodySmall, color = onSurface.copy(alpha = 0.6f))
                    RuleMatch.entries.forEach { mode ->
                        val selected = mode == matchMode
                        Box(
                            modifier = Modifier
                                .background(if (selected) accent.copy(alpha = 0.18f) else onSurface.copy(alpha = 0.05f), RoundedCornerShape(8.dp))
                                .border(1.dp, if (selected) accent else Color.Transparent, RoundedCornerShape(8.dp))
                                .pressBounce { onMatchModeChange(mode) }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(
                                if (mode == RuleMatch.ANY) "Any rule" else "All rules",
                                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                                color = if (selected) accent else onSurface.copy(alpha = 0.6f)
                            )
                        }
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Auto-file matches", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = onSurface)
                    Text(
                        if (autoFile) "New & existing matches are filed automatically." else "Rules run only when you tap Apply.",
                        style = MaterialTheme.typography.labelSmall,
                        color = onSurface.copy(alpha = 0.45f)
                    )
                }
                Switch(
                    checked = autoFile,
                    onCheckedChange = onAutoFileChange,
                    colors = SwitchDefaults.colors(checkedTrackColor = accent),
                    modifier = Modifier.testTag("space_autofile_switch")
                )
            }
        }
    }
}

/** A small pill that opens a dropdown to pick a rule field. */
@Composable
private fun RuleFieldDropdown(
    text: String,
    accent: Color,
    modifier: Modifier = Modifier,
    onSelect: (RuleField) -> Unit
) {
    RuleEnumDropdown(
        text = text,
        accent = accent,
        modifier = modifier,
        options = RuleField.entries.map { it.label to it },
        onSelect = onSelect
    )
}

/** A small pill that opens a dropdown to pick a rule operator. */
@Composable
private fun RuleOpDropdown(
    text: String,
    accent: Color,
    modifier: Modifier = Modifier,
    onSelect: (RuleOp) -> Unit
) {
    RuleEnumDropdown(
        text = text,
        accent = accent,
        modifier = modifier,
        options = RuleOp.entries.map { it.label to it },
        onSelect = onSelect
    )
}

@Composable
private fun <T> RuleEnumDropdown(
    text: String,
    accent: Color,
    modifier: Modifier = Modifier,
    options: List<Pair<String, T>>,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .background(accent.copy(alpha = 0.14f), RoundedCornerShape(8.dp))
                .border(1.dp, accent.copy(alpha = 0.4f), RoundedCornerShape(8.dp))
                .pressBounce { expanded = true }
                .padding(start = 12.dp, end = 6.dp, top = 7.dp, bottom = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(text, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = accent)
            Icon(Icons.Default.ArrowDropDown, contentDescription = "Choose", tint = accent, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (label, value) ->
                DropdownMenuItem(
                    text = { Text(label, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold)) },
                    onClick = {
                        onSelect(value)
                        expanded = false
                    }
                )
            }
        }
    }
}

/** Field-specific hint text for a rule's value input. */
private fun rulePlaceholder(field: RuleField): String = when (field) {
    RuleField.KEYWORD -> "e.g. diffusion"
    RuleField.TAG -> "e.g. transformers"
    RuleField.CATEGORY -> "e.g. agents"
    RuleField.SOURCE -> "ARXIV, GITHUB, HUGGING_FACE, TWEET"
    RuleField.AUTHOR -> "e.g. karpathy"
    RuleField.URL -> "e.g. github.com"
}

@Composable
private fun DeleteSpaceDialog(space: Space, tier: GlassTier, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    SlideUpCard(
        onDismissRequest = onDismiss,
        tier = tier,
        borderColor = MaterialTheme.colorScheme.error.copy(alpha = 0.3f),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
                val dismiss = LocalSlideUpDismiss.current
                Text("DELETE SPACE", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.error, letterSpacing = 1.sp))
                Text(
                    "Delete \"${space.name}\"? The ${space.count} bookmark${if (space.count == 1) "" else "s"} inside stay in your library — they're just unfiled from this Space.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f), RoundedCornerShape(14.dp))
                            .pressBounce { dismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Text("CANCEL", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)))
                    }
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(MaterialTheme.colorScheme.error, RoundedCornerShape(14.dp))
                            .pressBounce { onConfirm() }
                            .testTag("space_delete_confirm_${space.id}"),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("DELETE", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onError))
                    }
                }
    }
}

/**
 * Picks a Space (or removes membership) for a set of bookmarks. Shared by the feed's bulk action
 * bar and a single card's option sheet. [currentSpaceId] highlights the active membership when all
 * selected items share one.
 */
@Composable
internal fun AssignToSpaceDialog(
    spaces: List<Space>,
    currentSpaceId: String?,
    tier: GlassTier,
    onDismiss: () -> Unit,
    onAssign: (spaceId: String?) -> Unit,
    onCreateSpace: () -> Unit
) {
    SlideUpCard(
        onDismissRequest = onDismiss,
        tier = tier,
        contentPadding = 20.dp,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
                Text(
                    "MOVE TO SPACE",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary, letterSpacing = 1.sp),
                    modifier = Modifier.padding(bottom = 6.dp)
                )

                if (spaces.isEmpty()) {
                    Text(
                        "You don't have any Spaces yet.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        modifier = Modifier.padding(vertical = 4.dp)
                    )
                }

                spaces.forEach { space ->
                    val color = Color(space.color)
                    val selected = space.id == currentSpaceId
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp)
                            .background(if (selected) color.copy(alpha = 0.14f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.04f), RoundedCornerShape(12.dp))
                            .pressBounce { onAssign(space.id) }
                            .padding(horizontal = 12.dp)
                            .testTag("assign_space_${space.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Box(
                            modifier = Modifier.size(34.dp).background(color.copy(alpha = 0.9f), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(spaceIcon(space.icon), contentDescription = null, tint = CurioColors.onColor(color), modifier = Modifier.size(18.dp))
                        }
                        Text(space.name, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Text("${space.count}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                        if (selected) Icon(Icons.Default.Check, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
                    }
                }

                // Remove-from-space option (only meaningful when something is filed).
                if (currentSpaceId != null) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp)
                            .background(MaterialTheme.colorScheme.error.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                            .pressBounce { onAssign(null) }
                            .padding(horizontal = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(18.dp))
                        Text("Remove from Space", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.error)
                    }
                }

                // New space shortcut.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f), RoundedCornerShape(12.dp))
                        .pressBounce { onCreateSpace() }
                        .padding(horizontal = 12.dp)
                        .testTag("assign_new_space_button"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                    Text("New Space…", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.primary)
                }
    }
}
