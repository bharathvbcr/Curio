# Architecture Guideline

**Curio** is strictly organized according to **Clean Architecture** patterns, ensuring unidirectional flow, separation of concerns, and full testability.

## Directory Structure

```
com.example
├── data/                  # Remote & Local Data Management
│   ├── remote/            # Retrofit api, OAuth 2.0 PKCE, DTO structures
│   ├── local/             # Room Database definitions and Migrations
│   └── repo/              # Repository Concrete Implementations
├── domain/                # Pure Kotlin Business Logic (No Android dependency)
│   ├── model/             # Typed Models (Bookmark, AuthState, AuthChallenge)
│   ├── repo/              # Repository Interfaces (AuthRepository, BookmarkRepository)
│   └── usecase/           # Action controllers with high-cohesion operators
└── ui/                    # Presentation Layer (Jetpack Compose)
    ├── theme/             # Color, Type, Shape, and Glass Render classes
    ├── components/        # Reusable global design components (scaffolds, chips)
    └── screens/           # Module Screens with VM and UI States
```

## Non-Negotiable Contracts

1. **Named Functions ONLY**: Mega composables are decomposed into high-fidelity functional parts.
2. **Business/Presentation Separation**: Composables must remain simple, lightweight render structures reflecting immutable `UiState` objects.
3. **Sealed Errors**: All API, Rate Limits, and Auth failures compile straight into explicit typed error hierarchies.
