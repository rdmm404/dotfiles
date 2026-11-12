/* Adapted from imbypass/omarchy-theme-hook. */
:root {
    /* Match the tinted song-row hover, but stay opaque for menus and fades. */
    --omarchy-hover: color-mix(in srgb, var(--spice-text) 14%, var(--spice-main));
    --omarchy-press: color-mix(in srgb, var(--spice-text) 21%, var(--spice-main));
    --spice-highlight-elevated: var(--omarchy-hover);
}

.encore-dark-theme,
.encore-dark-theme .encore-base-set,
.encore-dark-theme .encore-app-frame-set,
.encore-dark-theme .encore-muted-accent-set {
    --background-highlight: var(--omarchy-hover) !important;
    --background-press: var(--omarchy-press) !important;
    --background-elevated-base: var(--spice-main-elevated) !important;
    --background-elevated-highlight: var(--omarchy-hover) !important;
    --background-elevated-press: var(--omarchy-press) !important;
}

/* Informational prompts, including the speaker/device activation callout. */
.encore-dark-theme .encore-announcement-set {
    --background-base: var(--spice-button-active) !important;
    --background-highlight: var(--spice-button-active) !important;
    --background-press: var(--spice-button-active) !important;
    --background-elevated-base: var(--spice-button-active) !important;
    --background-elevated-highlight: var(--spice-button-active) !important;
    --background-elevated-press: var(--spice-button-active) !important;
    --text-base: var(--spice-main) !important;
    --text-subdued: var(--spice-main) !important;
    --essential-base: var(--spice-main) !important;
    --essential-subdued: var(--spice-main) !important;
}

.encore-dark-theme .encore-announcement-set > * {
    --parents-essential-base: var(--spice-main) !important;
}

.main-nowPlayingBar-container {
    background-color: var(--background-base);
    border-radius: 0.5rem;
    padding: 0.5rem;
    color: var(--spice-text);
}

.main-entityHeader-backgroundColor,
.main-actionBarBackground-background,
.playlist-playlist-actionBarBackground-background,
.main-home-homeHeader {
    display: none !important;
}

.main-topBar-background,
.main-home-filterChipsSection {
    background-color: var(--spice-main) !important;
}

/* Spotify adds a black scrim over the sticky Home filters when scrolled. */
.main-home-filterChipsSection::after {
    background-color: transparent !important;
}

/* Shared carousel edge fades: Home shelves and sidebar recommendations. */
.search-searchCategory-contentArea {
    --carousel-start-chevron-gradient: var(--spice-main) !important;
    --carousel-end-chevron-gradient: var(--spice-main) !important;
}

/* Blend the sidebar artwork/title transition into the palette, not charcoal. */
.main-nowPlayingView-contextItemInfo::before {
    background: linear-gradient(
        rgba(var(--spice-rgb-main), 0) 0%,
        rgba(var(--spice-rgb-main), 0.45) 18%,
        var(--spice-main) 89% 96%
    ) !important;
}

/* Library sticky filter/header shadow (Spotify 1.2.96 generated classes). */
.HFowbNOgNPgtZSE4,
.pH4ZUdfvwTB_sRS_.ubsAl0Z3N0XZgmhy {
    box-shadow: none !important;
}
