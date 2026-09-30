/// Whether the history column is pinned to the sentence being spoken.
///
/// A reader who scrolls up is reading something, and yanking them back to the
/// bottom on the next sentence would make the column unusable for the one
/// thing it exists for. So scrolling up lets go, and there is a way back.
struct LiveFollow: Equatable {
    private(set) var isFollowing = true

    /// The way back is offered exactly when the list is not following.
    var showsJump: Bool { !isFollowing }

    mutating func scrolled(toBottom: Bool, userInitiated: Bool) {
        // New words, translations and resizing can move the bottom out of
        // view too. Only the reader can choose to stop following.
        if userInitiated || toBottom { isFollowing = toBottom }
    }

    mutating func jumped() {
        isFollowing = true
    }
}
