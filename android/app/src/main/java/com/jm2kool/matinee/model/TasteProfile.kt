package com.jm2kool.matinee.model

import kotlinx.serialization.Serializable

/// The character Matinee builds from your swipes.
@Serializable
data class Persona(
    val name: String,
    val emoji: String,
    val blurb: String,
    val topGenres: List<String>,
    val genreShares: List<Double>,      // 0…1, same order as topGenres
    val era: String,
    val traits: List<String>,
)

@Serializable
data class TasteProfile(
    val scores: Map<String, Double> = emptyMap(),      // genre name → score
    val liked: List<FilmRef> = emptyList(),
    val disliked: List<String> = emptyList(),          // show ids
    val likedYears: List<Int> = emptyList(),
    val seen: Int = 0,
    val persona: Persona? = null,
    val skipped: Boolean = false,
    val updatedAt: Long = System.currentTimeMillis(),
    // From your library: genres of shows you've saved, rated and liked.
    val libraryScores: Map<String, Double>? = null,
    val libraryYears: List<Int>? = null,
    val librarySignature: String? = null,
    val libraryFilms: Int? = null,
)
