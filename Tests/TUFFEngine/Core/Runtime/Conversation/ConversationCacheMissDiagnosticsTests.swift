import Testing
@testable import TUFFEngine

/// The cache-miss log names where a rendered prompt stops agreeing with the
/// cached tokens, so a silent cold start can be traced to its cause.
struct ConversationCacheMissDiagnosticsTests {
    @Test func reportsTheFirstDifferingTokenWithIdsOnBothSides() {
        let cached: [Int32] = Array(1...20)
        var rendered = cached + [50, 51]
        rendered[10] = 999
        let line = ConversationCache.prefixDivergence(
            renderedPromptIDs: rendered, cachedTokenIDs: cached, kvPosition: cached.count)
        #expect(line.contains("rendered=22 kvPosition=20"))
        #expect(line.contains("first difference at token 10"))
        #expect(line.contains("rendered[7,8,9,10,999,12,13,14,15]"))
        #expect(line.contains("cached[7,8,9,10,11,12,13,14,15]"))
    }

    @Test func clampsTheWindowAtBothEnds() {
        let line = ConversationCache.prefixDivergence(
            renderedPromptIDs: [9, 2, 3], cachedTokenIDs: [1, 2, 3], kvPosition: 3)
        #expect(line.contains("first difference at token 0"))
        #expect(line.contains("rendered[9,2,3]"))
        #expect(line.contains("cached[1,2,3]"))
    }

    @Test func reportsAShorterRenderedPrompt() {
        let line = ConversationCache.prefixDivergence(
            renderedPromptIDs: [1, 2, 3], cachedTokenIDs: [1, 2, 3, 4, 5], kvPosition: 5)
        #expect(line.contains("rendered prompt shorter"))
    }

    @Test func reportsANilRenderedPrompt() {
        let line = ConversationCache.prefixDivergence(
            renderedPromptIDs: nil, cachedTokenIDs: [1, 2], kvPosition: 2)
        #expect(line.contains("rendered prompt nil"))
    }

    @Test func reportsAnIdenticalPrefixThatStillMissed() {
        let line = ConversationCache.prefixDivergence(
            renderedPromptIDs: [1, 2, 3, 4], cachedTokenIDs: [1, 2, 3], kvPosition: 3)
        #expect(line.contains("no difference in the first 3 tokens"))
    }
}
