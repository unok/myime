public enum InputPiece: Sendable, Equatable, Hashable {
    public enum Modifier: Sendable, Hashable {
        case shift
    }

    case character(Character)
    case compositionSeparator
    case key(intention: Character?, modifiers: Set<Modifier>)
}
