import Foundation

/// The three "conversation fit" chips for the Taipei beta profile
/// model. They are SOFT context — they shape discovery sort order and
/// chat openers, never filter rows out and never gate any flow.
///
/// Raw values match the CHECK constraints in migration 0034. Adding a
/// case requires updating both the migration and the localization
/// catalog at the same time.

/// Why the user is on Getalong right now. Maps to
/// `profiles.connection_intent`.
enum ConnectionIntent: String, CaseIterable, Identifiable, Codable {
    case slowChat    = "slow_chat"
    case newFriends  = "new_friends"
    case datingOpen  = "dating_open"
    case notSure     = "not_sure"

    var id: String { rawValue }

    /// Long-form label, suitable for picker rows and the profile card.
    var localizedTitle: String {
        switch self {
        case .slowChat:   return String(localized: "fit.intent.slowChat.title")
        case .newFriends: return String(localized: "fit.intent.newFriends.title")
        case .datingOpen: return String(localized: "fit.intent.datingOpen.title")
        case .notSure:    return String(localized: "fit.intent.notSure.title")
        }
    }

    /// Short label used on the compact chip on a Discovery card.
    var localizedShort: String {
        switch self {
        case .slowChat:   return String(localized: "fit.intent.slowChat.short")
        case .newFriends: return String(localized: "fit.intent.newFriends.short")
        case .datingOpen: return String(localized: "fit.intent.datingOpen.short")
        case .notSure:    return String(localized: "fit.intent.notSure.short")
        }
    }
}

/// User's daily rhythm. Maps to `profiles.lifestyle_rhythm`.
enum LifestyleRhythm: String, CaseIterable, Identifiable, Codable {
    case earlyBird      = "early_bird"
    case nightOwl       = "night_owl"
    case weekendPerson  = "weekend_person"
    case flexible       = "flexible"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .earlyBird:     return String(localized: "fit.rhythm.earlyBird.title")
        case .nightOwl:      return String(localized: "fit.rhythm.nightOwl.title")
        case .weekendPerson: return String(localized: "fit.rhythm.weekendPerson.title")
        case .flexible:      return String(localized: "fit.rhythm.flexible.title")
        }
    }

    var localizedShort: String {
        switch self {
        case .earlyBird:     return String(localized: "fit.rhythm.earlyBird.short")
        case .nightOwl:      return String(localized: "fit.rhythm.nightOwl.short")
        case .weekendPerson: return String(localized: "fit.rhythm.weekendPerson.short")
        case .flexible:      return String(localized: "fit.rhythm.flexible.short")
        }
    }
}

/// What the user wants to talk about. Maps to
/// `profiles.conversation_domain`.
enum ConversationDomain: String, CaseIterable, Identifiable, Codable {
    case dailyLife   = "daily_life"
    case foodCafes   = "food_cafes"
    case cityWalks   = "city_walks"
    case musicFilms  = "music_films"
    case workStudy   = "work_study"
    case travel
    case values
    case random

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .dailyLife:  return String(localized: "fit.domain.dailyLife.title")
        case .foodCafes:  return String(localized: "fit.domain.foodCafes.title")
        case .cityWalks:  return String(localized: "fit.domain.cityWalks.title")
        case .musicFilms: return String(localized: "fit.domain.musicFilms.title")
        case .workStudy:  return String(localized: "fit.domain.workStudy.title")
        case .travel:     return String(localized: "fit.domain.travel.title")
        case .values:     return String(localized: "fit.domain.values.title")
        case .random:     return String(localized: "fit.domain.random.title")
        }
    }

    var localizedShort: String {
        switch self {
        case .dailyLife:  return String(localized: "fit.domain.dailyLife.short")
        case .foodCafes:  return String(localized: "fit.domain.foodCafes.short")
        case .cityWalks:  return String(localized: "fit.domain.cityWalks.short")
        case .musicFilms: return String(localized: "fit.domain.musicFilms.short")
        case .workStudy:  return String(localized: "fit.domain.workStudy.short")
        case .travel:     return String(localized: "fit.domain.travel.short")
        case .values:     return String(localized: "fit.domain.values.short")
        case .random:     return String(localized: "fit.domain.random.short")
        }
    }
}
