import Foundation
import Testing
@testable import Curio

// =============================================================================================
// Source extraction — port of app/src/test/java/com/example/SourceExtractionTest.kt
// =============================================================================================

/// Pure tests for the primary-source URL/ID extraction regexes that drive `SourceResolver`'s
/// priority logic (arXiv ids, bare arXiv ids, DOIs).
///
/// Port of `app/src/test/java/com/example/SourceExtractionTest.kt` (pure-JVM JUnit). The regexes
/// under test live on the iOS clients exactly as they did on Android:
/// `ArxivClient.arxivIdRegex` / `ArxivClient.arxivBareRegex` (Kotlin `ARXIV_ID_REGEX` /
/// `ARXIV_BARE_REGEX`) and `CrossrefClient.doiRegex` (Kotlin `DOI_REGEX`), with byte-identical
/// patterns per CONVENTIONS §10.
@Suite("SourceExtraction (mirrors SourceExtractionTest.kt)")
struct SourceExtractionTests {

    /// Kotlin: `ArxivClient.ARXIV_ID_REGEX.find(s)?.groupValues?.get(1)`.
    private func arxivId(_ s: String) -> String? {
        s.firstMatch(of: ArxivClient.arxivIdRegex).map { String($0.1) }
    }

    /// Kotlin: `ArxivClient.ARXIV_BARE_REGEX.find(s)?.groupValues?.get(1)`.
    private func bareArxiv(_ s: String) -> String? {
        s.firstMatch(of: ArxivClient.arxivBareRegex).map { String($0.1) }
    }

    /// Kotlin: `CrossrefClient.DOI_REGEX.find(s)?.groupValues?.get(1)`.
    private func doi(_ s: String) -> String? {
        s.firstMatch(of: CrossrefClient.doiRegex).map { String($0.1) }
    }

    /// Kotlin: `arxiv id from abs and pdf urls`.
    @Test("arxiv id from abs and pdf urls")
    func arxivIdFromAbsAndPdfUrls() {
        #expect(arxivId("https://arxiv.org/abs/2312.00752") == "2312.00752")
        #expect(arxivId("https://arxiv.org/pdf/2301.00001v2") == "2301.00001v2")
        #expect(arxivId("see ar5iv.org/abs/2305.12345 for the rendered version") == "2305.12345")
    }

    /// Kotlin: `arxiv id regex ignores non-arxiv urls`.
    @Test("arxiv id regex ignores non-arxiv urls")
    func arxivIdRegexIgnoresNonArxivUrls() {
        #expect(arxivId("https://github.com/owner/repo") == nil)
        #expect(arxivId("https://example.com/abs/123") == nil)
    }

    /// Kotlin: `bare arxiv id found in free text but not short decimals`.
    @Test("bare arxiv id found in free text but not short decimals")
    func bareArxivIdFoundInFreeText() {
        #expect(bareArxiv("the Mamba paper 2312.00752 is great") == "2312.00752")
        #expect(bareArxiv("2301.00001v3") == "2301.00001v3")
        #expect(bareArxiv("version 12.34 of the spec") == nil)
    }

    /// Kotlin: `doi matched in doi-org url and bare, case-insensitive`.
    @Test("doi matched in doi-org url and bare, case-insensitive")
    func doiMatchedInUrlAndBare() {
        #expect(doi("https://doi.org/10.1038/s41586-021-03819-2") == "10.1038/s41586-021-03819-2")
        #expect(doi("cite 10.1145/3292500.3330701 here") == "10.1145/3292500.3330701")
        // DOI prefixes are case-insensitive per the regex option.
        #expect(doi("DOI 10.1000/XYZ123") == "10.1000/XYZ123")
    }

    /// Kotlin: `doi regex ignores non-doi text`.
    @Test("doi regex ignores non-doi text")
    func doiRegexIgnoresNonDoiText() {
        #expect(doi("just some text with 10 and a slash / but no doi") == nil)
        #expect(doi("https://github.com/owner/repo") == nil)
    }
}

// =============================================================================================
// Source clients — port of app/src/test/java/com/example/SourceClientTest.kt
// =============================================================================================

/// A `URLProtocol` stub standing in for the Android `MockWebServer`: every request made through a
/// session configured with this protocol is answered by the (single, shared) `handler`. The suite
/// below is `.serialized` because the handler is process-global state.
final class MockURLProtocol: URLProtocol {
    /// The canned response factory. `nonisolated(unsafe)` because URLProtocol offers no injection
    /// seam other than a static; the owning suite is serialized so there is no concurrent mutation.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (statusCode: Int, body: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (statusCode, body) = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Exercises the primary-source HTTP clients against a stubbed URL-loading layer (the iOS
/// `HTTPClient` accepts caller-supplied `URLSession`s, mirroring the injectable base URLs the
/// Android test relied on), so the arXiv Atom parser and Crossref JSON parser are tested
/// end-to-end without hitting the network.
///
/// Port of `app/src/test/java/com/example/SourceClientTest.kt` (JUnit + Robolectric +
/// MockWebServer). MockWebServer becomes `MockURLProtocol`; Robolectric's `android.util.Xml`
/// becomes Foundation's `XMLParser` inside `ArxivClient.parseAtom`.
///
/// DEVIATION (documented, not a weakening): the Kotlin `arxiv non-2xx yields null` test enqueued a
/// 503. On iOS a 503 takes `ArxivClient.fetchPaper`'s retry path (three attempts with 2s/4s/6s
/// backoff sleeps — ~12s of wall time), so this port answers 500 instead, which exercises the same
/// "hard non-2xx → nil" contract via the immediate give-up branch.
@Suite("SourceClient (mirrors SourceClientTest.kt)", .serialized)
struct SourceClientTests {

    /// Builds an `HTTPClient` whose sessions are answered entirely by `MockURLProtocol`.
    private func stubbedHTTPClient() -> HTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return HTTPClient(primarySession: session, metadataSession: session)
    }

    /// Kotlin: `arxiv atom is parsed into ArxivMeta`.
    @Test("arxiv atom is parsed into ArxivMeta")
    func arxivAtomIsParsedIntoArxivMeta() async throws {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>http://arxiv.org/abs/2312.00752v1</id>
            <title>Mamba: Linear-Time Sequence Modeling</title>
            <summary>We introduce a selective state space model.</summary>
            <published>2023-12-01T00:00:00Z</published>
            <author><name>Albert Gu</name></author>
            <author><name>Tri Dao</name></author>
            <category term="cs.LG"/>
          </entry>
        </feed>
        """
        MockURLProtocol.handler = { _ in (statusCode: 200, body: Data(atom.utf8)) }
        defer { MockURLProtocol.handler = nil }

        let client = ArxivClient(http: stubbedHTTPClient(), baseUrl: "https://mock.test/api/query")
        let meta = try #require(await client.fetchPaper("2312.00752"))
        #expect(meta.id == "2312.00752") // version suffix stripped
        #expect(meta.title.contains("Mamba"))
        #expect(meta.authors == ["Albert Gu", "Tri Dao"])
        #expect(meta.published == "2023-12-01")
        #expect(meta.categories == ["cs.LG"])
    }

    /// Kotlin: `arxiv non-2xx yields null` (503 there; 500 here — see the suite doc comment).
    @Test("arxiv non-2xx yields nil")
    func arxivNon2xxYieldsNil() async {
        MockURLProtocol.handler = { _ in (statusCode: 500, body: Data()) }
        defer { MockURLProtocol.handler = nil }

        let client = ArxivClient(http: stubbedHTTPClient(), baseUrl: "https://mock.test/api/query")
        let meta = await client.fetchPaper("2312.00752")
        #expect(meta == nil)
    }

    /// Kotlin: `crossref json is parsed and JATS abstract is stripped`.
    @Test("crossref json is parsed and JATS abstract is stripped")
    func crossrefJsonIsParsedAndJatsAbstractIsStripped() async throws {
        let json = """
        {"message":{
          "DOI":"10.1038/s41586-021-03819-2",
          "title":["Highly accurate protein structure prediction with AlphaFold"],
          "author":[{"given":"John","family":"Jumper"},{"given":"Demis","family":"Hassabis"}],
          "abstract":"<jats:p>AlphaFold predicts structures.</jats:p>",
          "container-title":["Nature"],
          "type":"journal-article",
          "issued":{"date-parts":[[2021,7,15]]}
        }}
        """
        MockURLProtocol.handler = { _ in (statusCode: 200, body: Data(json.utf8)) }
        defer { MockURLProtocol.handler = nil }

        let client = CrossrefClient(http: stubbedHTTPClient(), baseUrl: "https://mock.test/works/")
        let meta = try #require(await client.fetchWork("10.1038/s41586-021-03819-2"))
        #expect(meta.doi == "10.1038/s41586-021-03819-2")
        #expect(meta.title.contains("AlphaFold"))
        #expect(meta.authors == ["John Jumper", "Demis Hassabis"])
        #expect(meta.containerTitle == "Nature")
        #expect(meta.published == "2021-07-15")
        #expect(meta.abstract == "AlphaFold predicts structures.")
    }
}
