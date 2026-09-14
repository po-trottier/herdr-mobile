//! Phase 23 security review (`docs/90-implementation-plan.md` §Phase 23, item 1): fuzzes
//! `/host/<handle>`, `/device/<handle>`, `/healthz` and `/metrics` against a real relay
//! router served on a real loopback TCP port, and asserts the relay never panics or hangs
//! and always answers with a defined, documented outcome (R-12-021, R-12-030). Results are
//! written up in `docs/security/review-pack/fuzz.md`.
//!
//! Self-contained, like `tests/limits.rs`: this file needs `HERDR_RELAY_CONNECTION_RATE`
//! raised (so the R-12-031 connection-rate limiter, exercised on its own terms in
//! `tests/limits.rs` and `tests/handle_guessing.rs`, never confounds a handle-format
//! fuzzing run) and both routers `tests/support/mod.rs`'s `Relay` does not expose (its
//! `router()` convenience is main-router-only; `/metrics` lives on a second router,
//! R-12-024), so it builds its own harness from `herdr_relay_hub::routes::build()` rather
//! than extending the shared one.
//!
//! No `cargo-fuzz`/`libfuzzer-sys`/`arbitrary` dependency (R-41-042): a fixed-seed
//! splitmix64 generator feeding a plain loop of real WebSocket/HTTP requests is enough to
//! fuzz a small, already-open-source HTTP surface, and a fixed seed makes a failing run
//! reproducible instead of a one-off flake.

use std::net::SocketAddr;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;

/// How long any single fuzz probe waits before it counts as a hang.
const PROBE_TIMEOUT: Duration = Duration::from_secs(2);

/// A fixed-seed splitmix64 generator (stdlib has no stable RNG: `std::random` is gated
/// behind the unstable `random` feature, rust-lang/rust#130703). Deterministic on
/// purpose, so a failing case reproduces on the next run instead of flaking.
struct Prng(u64);

impl Prng {
    fn new(seed: u64) -> Self {
        Self(seed)
    }

    fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    fn below(&mut self, bound: usize) -> usize {
        (self.next_u64() % bound as u64) as usize
    }

    fn byte(&mut self) -> u8 {
        (self.next_u64() % 256) as u8
    }
}

fn random_bytes(rng: &mut Prng, alphabet: &[u8], len: usize) -> Vec<u8> {
    (0..len)
        .map(|_| alphabet[rng.below(alphabet.len())])
        .collect()
}

/// Every byte outside RFC 3986's unreserved set becomes `%XX`, so any input — including
/// invalid UTF-8, control bytes, and literal `/` — survives as one URL path segment
/// (R-12-021's `<handle>` is a single segment; a raw `/` would just split the path).
fn percent_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 3);
    for &b in bytes {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The malformed-handle corpus: every category R-12-021's checkbox names, plus randomized
/// noise to reach a few hundred cases. Byte-level (not `String`) so it can include invalid
/// UTF-8, which a real attacker's raw bytes are not obliged to avoid.
fn malformed_handle_corpus() -> Vec<(&'static str, Vec<u8>)> {
    let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut rng = Prng::new(0xF00D_CAFE_1234_5678);
    let mut v: Vec<(&'static str, Vec<u8>)> = Vec::new();

    v.push(("empty", Vec::new()));
    for len in [1, 2, 7, 15, 20, 21] {
        v.push(("too_short", random_bytes(&mut rng, alphabet, len)));
    }
    for len in [23, 24, 30, 64, 256, 4096, 20_000] {
        v.push(("too_long", random_bytes(&mut rng, alphabet, len)));
    }
    // A base64url-shaped 22-char string with exactly one forbidden byte substituted in,
    // one case per forbidden byte (R-12-021's "unpadded base64url" charset boundary).
    for &bad in b"+/=!@#$%^&*()\\\"'`~<>,.;:|[]{} \t\r\n".iter() {
        let mut s = random_bytes(&mut rng, alphabet, 22);
        let pos = rng.below(22);
        s[pos] = bad;
        v.push(("bad_char", s));
    }
    for s in [
        "../../../etc/passwd",
        "....//....//etc/shadow",
        "/etc/passwd",
        "..\\..\\windows\\system32",
        "a/../../b",
        "%2e%2e%2f%2e%2e%2f",
    ] {
        v.push(("path_traversal", s.as_bytes().to_vec()));
    }
    for s in [
        "héllo-wörld-ünïcödé-22",
        "日本語のハンドル文字列です",
        "🎉🔥💀🚀handle-emoji",
        "Ω≈ç√∫˜µ≤≥÷",
    ] {
        v.push(("unicode", s.as_bytes().to_vec()));
    }
    v.push(("null_bytes", vec![0u8; 22]));
    v.push(("null_bytes", b"abc\0def\0ghi\0jkl\0mno\0p".to_vec()));
    v.push(("null_bytes", vec![0u8]));
    v.push(("invalid_utf8", vec![0xFF, 0xFE, 0xFD, 0x80, 0x81]));
    v.push(("invalid_utf8", vec![0xC0, 0xC1, 0xC1, 0xC1]));
    for _ in 0..180 {
        let len = rng.below(40);
        v.push(("random_noise", (0..len).map(|_| rng.byte()).collect()));
    }
    v
}

/// One relay instance, both routers (`herdr_relay_hub::routes::build()`), each on its own
/// loopback port — mirrors `main.rs`'s own two-listener wiring (R-12-024).
async fn start_relay() -> (
    SocketAddr,
    SocketAddr,
    tokio::task::JoinHandle<()>,
    tokio::task::JoinHandle<()>,
) {
    let main_listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("binding a loopback ephemeral port must succeed in a test");
    let metrics_listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("binding a loopback ephemeral port must succeed in a test");
    let main_addr = main_listener
        .local_addr()
        .expect("bound socket has an address");
    let metrics_addr = metrics_listener
        .local_addr()
        .expect("bound socket has an address");
    let (app, metrics_app) = herdr_relay_hub::routes::build();
    let main_server = tokio::spawn(async move {
        axum::serve(
            main_listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .expect("the test relay's main router must not fail to serve");
    });
    let metrics_server = tokio::spawn(async move {
        axum::serve(metrics_listener, metrics_app)
            .await
            .expect("the test relay's metrics router must not fail to serve");
    });
    (main_addr, metrics_addr, main_server, metrics_server)
}

/// One WebSocket-upgrade fuzz probe against `/<role>/<percent-encoded handle>`, classified
/// into one outcome bucket. Every branch returns; none can panic on a well-formed relay
/// reply, so any real relay panic surfaces as a test failure instead of being swallowed.
async fn probe_handle(addr: SocketAddr, role: &str, raw: &[u8]) -> String {
    let url = format!("ws://{addr}/{role}/{}", percent_encode(raw));
    let mut request = match url.as_str().into_client_request() {
        Ok(r) => r,
        Err(e) => return format!("client_request_invalid:{e}"),
    };
    request.headers_mut().insert(
        "sec-websocket-protocol",
        "herdr-relay.v1"
            .parse()
            .expect("static header value always parses"),
    );
    match tokio::time::timeout(PROBE_TIMEOUT, tokio_tungstenite::connect_async(request)).await {
        Err(_) => "hang_on_connect".to_owned(),
        Ok(Err(tokio_tungstenite::tungstenite::Error::Http(response))) => {
            format!("http_rejected_{}", response.status().as_u16())
        }
        Ok(Err(other)) => format!("connect_error:{other}"),
        Ok(Ok((mut stream, _response))) => {
            let first = match tokio::time::timeout(PROBE_TIMEOUT, stream.next()).await {
                Err(_) => return "hang_after_upgrade".to_owned(),
                Ok(None) => return "upgraded_then_eof".to_owned(),
                Ok(Some(Err(e))) => return format!("upgraded_then_transport_error:{e}"),
                Ok(Some(Ok(message))) => message,
            };
            // R-11-116: a plaintext `error` frame precedes the close frame. Read past it to
            // reach the close code, the actual "defined outcome" this probe classifies on.
            let second = match first {
                WsMessage::Close(_) => first,
                WsMessage::Text(_) => {
                    match tokio::time::timeout(PROBE_TIMEOUT, stream.next()).await {
                        Err(_) => return "hang_after_error_frame".to_owned(),
                        Ok(None) => return "upgraded_then_eof_after_error_frame".to_owned(),
                        Ok(Some(Err(e))) => return format!("upgraded_then_transport_error:{e}"),
                        Ok(Some(Ok(message))) => message,
                    }
                }
                other => return format!("upgraded_then_message:{other:?}"),
            };
            match second {
                WsMessage::Close(Some(frame)) => format!("closed_{}", u16::from(frame.code)),
                WsMessage::Close(None) => "closed_no_code".to_owned(),
                other => format!("upgraded_then_unexpected_second_message:{other:?}"),
            }
        }
    }
}

/// `/healthz` is proven reachable on `addr`, the same loopback address that serves the
/// `/host`/`/device` WebSocket upgrades — i.e. `/healthz` binds the same acceptor as the
/// WS routes rather than a separate listener (R-12-023) — and that the relay's task
/// survived the fuzz barrage (a panic would have killed it instead of answering).
async fn assert_relay_still_answers_healthz(addr: SocketAddr) {
    let response = raw_http(
        addr,
        b"GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
    )
    .await;
    let text = String::from_utf8_lossy(&response);
    assert!(
        text.starts_with("HTTP/1.1 200") && text.ends_with("ok"),
        "the relay must still answer /healthz with 200 \"ok\" after the fuzz barrage \
         (a panic would have killed its task instead); got {text:?}"
    );
}

#[tokio::test]
async fn fuzzing_host_and_device_handles_never_crashes_the_relay() {
    // Raised so R-12-031's separate connection-rate limiter (proven on its own terms in
    // `tests/limits.rs` and `tests/handle_guessing.rs`) never turns a handle-format probe
    // into a `rate_limited` close instead of the `protocol_error` this test expects.
    // Safety: no other test in this binary reads or writes this variable while this
    // `#[tokio::test]` runs (single sequential function, like `tests/limits.rs`'s own).
    unsafe {
        std::env::set_var("HERDR_RELAY_CONNECTION_RATE", "1000000");
    }
    let (addr, _metrics_addr, main_server, metrics_server) = start_relay().await;
    let corpus = malformed_handle_corpus();

    let mut outcomes: std::collections::BTreeMap<String, usize> = std::collections::BTreeMap::new();
    let mut unsafe_outcomes = Vec::new();
    for role in ["host", "device"] {
        for (category, raw) in &corpus {
            let outcome = probe_handle(addr, role, raw).await;
            *outcomes.entry(format!("{category}/{outcome}")).or_insert(0) += 1;
            // Three documented, non-crashing outcomes: `protocol_error` (4003, R-12-021)
            // once a syntactically well-formed UTF-8 path segment fails `Handle::from_str`;
            // an HTTP 400 when the percent-decoded segment is not valid UTF-8 at all (axum's
            // `Path<String>` extractor rejects it before the WS layer ever sees it); and an
            // HTTP 404 when the segment decodes empty or otherwise matches no route.
            let safe = matches!(
                outcome.as_str(),
                "closed_4003" | "http_rejected_400" | "http_rejected_404"
            );
            if !safe {
                unsafe_outcomes.push(format!("{role} {category}: {outcome}"));
            }
        }
    }
    println!(
        "fuzz_endpoints host/device corpus size per role: {}",
        corpus.len()
    );
    for (outcome, count) in &outcomes {
        println!("  {outcome}: {count}");
    }

    assert!(
        unsafe_outcomes.is_empty(),
        "unexpected/unsafe outcome(s) for a malformed handle: {unsafe_outcomes:?}"
    );

    assert_relay_still_answers_healthz(addr).await;

    main_server.abort();
    metrics_server.abort();
    unsafe {
        std::env::remove_var("HERDR_RELAY_CONNECTION_RATE");
    }
}

/// A syntactically valid handle nobody registered (R-12-021's `<handle>` boundary is
/// distinct from R-11-118's "no Host here" case), and R-12-030's frame-size boundary,
/// exercised against the same running relay so both paths are proven never to crash it.
#[tokio::test]
async fn valid_handle_edge_cases_are_handled_without_crashing() {
    let (addr, _metrics_addr, main_server, metrics_server) = start_relay().await;
    // A 22-char base64url handle whose trailing partial group decodes cleanly (the same
    // shape `tests/limits.rs`'s own `fixture_handle` uses), never registered as a Host.
    let handle = "9AAAAAAAAAAAAAAAAAAAAA";

    // A Device pointed at an unregistered-but-well-formed handle: R-12-021 accepts the
    // upgrade and the registration frame; R-11-118's session layer then refuses with
    // `handle_unknown` (4001), not a crash and not `protocol_error`.
    let url = format!("ws://{addr}/device/{handle}");
    let mut request = url
        .as_str()
        .into_client_request()
        .expect("a fixed loopback ws URL always builds a valid request");
    request.headers_mut().insert(
        "sec-websocket-protocol",
        "herdr-relay.v1"
            .parse()
            .expect("static header value always parses"),
    );
    let (mut stream, _response) = tokio_tungstenite::connect_async(request)
        .await
        .expect("the relay must accept the WebSocket upgrade even for an unknown handle");
    stream
        .send(WsMessage::Text(
            r#"{"type":"device_register","protocol":1}"#.into(),
        ))
        .await
        .expect("send must succeed on a live socket");
    let error_frame = tokio::time::timeout(PROBE_TIMEOUT, stream.next())
        .await
        .expect("the relay must reply, not hang, for an unknown handle")
        .expect("a message must arrive")
        .expect("no transport error");
    assert!(
        matches!(&error_frame, WsMessage::Text(t) if t.contains("handle_unknown")),
        "expected the R-11-116 handle_unknown error frame first, got {error_frame:?}"
    );
    let close = tokio::time::timeout(PROBE_TIMEOUT, stream.next())
        .await
        .expect("the relay must close, not hang, after handle_unknown")
        .expect("a message must arrive")
        .expect("no transport error");
    match close {
        WsMessage::Close(Some(frame)) => {
            assert_eq!(
                u16::from(frame.code),
                4001,
                "expected handle_unknown's close code 4001"
            );
        }
        other => panic!("expected a Close(4001) frame, got {other:?}"),
    }

    // R-12-030's frame-size boundary. Register a real Host, then probe three sizes against
    // this crate's own `MAX_FRAME_BYTES` (`crates/herdr-relay-hub/src/routes.rs`), which is
    // 1 MiB (1_048_576 bytes) — not the 65535-byte ceiling `docs/12-relay-hosting.md`
    // R-12-030 currently documents. This mismatch is a genuine finding, recorded in
    // `docs/security/review-pack/fuzz.md` rather than silently patched here (Phase 23 owns
    // no path).
    let host_url = format!("ws://{addr}/host/{handle}");
    let mut host_request = host_url
        .as_str()
        .into_client_request()
        .expect("a fixed loopback ws URL always builds a valid request");
    host_request.headers_mut().insert(
        "sec-websocket-protocol",
        "herdr-relay.v1"
            .parse()
            .expect("static header value always parses"),
    );
    let (mut host, _response) = tokio_tungstenite::connect_async(host_request)
        .await
        .expect("the relay must accept the Host upgrade");
    host.send(WsMessage::Text(
        r#"{"type":"host_register","protocol":1}"#.into(),
    ))
    .await
    .expect("send must succeed on a live socket");
    let joined = tokio::time::timeout(PROBE_TIMEOUT, host.next())
        .await
        .expect("the relay must reply to registration")
        .expect("a message must arrive")
        .expect("no transport error");
    assert!(
        matches!(&joined, WsMessage::Text(t) if t.contains("session_joined")),
        "expected session_joined, got {joined:?}"
    );

    // 65536 bytes: over the *documented* 65535-byte ceiling, but under the *coded* 1 MiB
    // one. No Device is connected, so there is nothing to forward to; the only observable
    // question is whether the Host connection survives (it must, per the code as written).
    host.send(WsMessage::Binary(vec![7u8; 65_536].into()))
        .await
        .expect("send must succeed on a live socket");
    // 1_048_576 bytes exactly: the coded boundary itself, still accepted (`> `, not `>=`).
    host.send(WsMessage::Binary(vec![7u8; 1_048_576].into()))
        .await
        .expect("send must succeed on a live socket");
    // 1_048_577 bytes: one byte over the coded boundary — this one must be rejected.
    host.send(WsMessage::Binary(vec![7u8; 1_048_577].into()))
        .await
        .expect("send must succeed on a live socket");
    let reply = tokio::time::timeout(PROBE_TIMEOUT, host.next())
        .await
        .expect("the relay must close, not hang, once the 1 MiB boundary is crossed")
        .expect("a message must arrive")
        .expect("no transport error");
    match reply {
        WsMessage::Close(Some(frame)) => {
            assert_eq!(
                u16::from(frame.code),
                4007,
                "expected frame_too_large's close code 4007 once the frame exceeded 1 MiB"
            );
        }
        other => panic!("expected a Close(4007) frame, got {other:?}"),
    }

    assert_relay_still_answers_healthz(addr).await;
    main_server.abort();
    metrics_server.abort();
}

/// Sends `request` over a fresh raw TCP connection (always `Connection: close`, so the
/// server's own EOF ends the read loop instead of a full-timeout wait per probe) and
/// returns whatever bytes came back before EOF, an error, or [`PROBE_TIMEOUT`].
async fn raw_http(addr: SocketAddr, request: &[u8]) -> Vec<u8> {
    let mut stream = match tokio::time::timeout(PROBE_TIMEOUT, TcpStream::connect(addr)).await {
        Ok(Ok(s)) => s,
        _ => return Vec::new(),
    };
    if tokio::time::timeout(PROBE_TIMEOUT, stream.write_all(request))
        .await
        .is_err()
    {
        return Vec::new();
    }
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        match tokio::time::timeout(PROBE_TIMEOUT, stream.read(&mut chunk)).await {
            Ok(Ok(0)) | Ok(Err(_)) | Err(_) => break,
            Ok(Ok(n)) => {
                buf.extend_from_slice(&chunk[..n]);
                if buf.len() > 1_048_576 {
                    break;
                }
            }
        }
    }
    buf
}

fn status_line(response: &[u8]) -> String {
    let text = String::from_utf8_lossy(response);
    match text.lines().next() {
        Some(line) if line.starts_with("HTTP/") => line.to_owned(),
        _ if response.is_empty() => "no_response".to_owned(),
        _ => "unparseable_response".to_owned(),
    }
}

/// Builds a raw HTTP/1.1 request line + headers for one fuzz case. `marker` is a
/// per-request random token embedded in the query string and a header value, so the
/// leak check below can prove the response never reflects request content back.
fn build_request(
    method: &str,
    path: &str,
    query: &str,
    extra_headers: &str,
    marker: &str,
) -> Vec<u8> {
    let target = if query.is_empty() {
        path.to_owned()
    } else {
        format!("{path}?{query}&probe={marker}")
    };
    format!(
        "{method} {target} HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Probe-Marker: {marker}\r\n{extra_headers}Connection: close\r\n\r\n"
    )
    .into_bytes()
}

#[tokio::test]
async fn fuzzing_healthz_and_metrics_never_panics_or_leaks() {
    let (main_addr, metrics_addr, main_server, metrics_server) = start_relay().await;
    let mut rng = Prng::new(0xABCD_1234_5678_EF01);

    let methods = [
        "GET", "get", "Get", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE",
        "CONNECT", "FOOBAR", "", "G E T",
    ];
    let queries = [
        "",
        "a=1&b=2",
        "handle=n6Loxf94CfyIO6hOxlaHvA",
        "session=00000000-0000-0000-0000-000000000000",
        "%00",
        "%0d%0aX-Injected:%20evil",
        "../../etc/passwd",
        "<script>alert(1)</script>",
        "'; DROP TABLE handles; --",
    ];
    let header_variants = [
        String::new(),
        "X-Forwarded-For: 10.0.0.1\r\n".to_owned(),
        format!("X-Long: {}\r\n", "a".repeat(8_000)),
        "X-Dup: 1\r\nX-Dup: 2\r\nX-Dup: 3\r\n".to_owned(),
        "X-Unicode: héllo-日本語-🎉\r\n".to_owned(),
    ];

    let mut outcomes: std::collections::BTreeMap<String, usize> = std::collections::BTreeMap::new();
    let mut total = 0usize;
    let mut leaked = Vec::new();
    for &(addr, path) in &[(main_addr, "/healthz"), (metrics_addr, "/metrics")] {
        for &method in &methods {
            for &query in &queries {
                for headers in &header_variants {
                    let marker = format!("PROBE-{:016X}", rng.next_u64());
                    let request = build_request(method, path, query, headers, &marker);
                    let response = raw_http(addr, &request).await;
                    total += 1;
                    *outcomes.entry(status_line(&response)).or_insert(0) += 1;
                    if response
                        .windows(marker.len())
                        .any(|window| window == marker.as_bytes())
                    {
                        leaked.push(format!("{method} {path}?{query} leaked marker {marker}"));
                    }
                }
            }
        }
    }
    println!("fuzz_endpoints healthz/metrics total requests: {total}");
    for (outcome, count) in &outcomes {
        println!("  {outcome}: {count}");
    }

    assert!(
        leaked.is_empty(),
        "the response reflected fuzzed request content back to the caller: {leaked:?}"
    );
    for outcome in outcomes.keys() {
        assert!(
            !outcome.starts_with("HTTP/1.1 5"),
            "a 5xx response means the handler errored/panicked instead of returning a defined outcome: {outcome}"
        );
    }

    // The barrage must not have taken the relay down: both endpoints still answer cleanly.
    let healthz = raw_http(
        main_addr,
        b"GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
    )
    .await;
    let healthz_text = String::from_utf8_lossy(&healthz);
    assert!(
        healthz_text.starts_with("HTTP/1.1 200") && healthz_text.ends_with("ok"),
        "the relay must still answer /healthz cleanly after the fuzz barrage; got {healthz_text:?}"
    );
    let metrics = raw_http(
        metrics_addr,
        b"GET /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
    )
    .await;
    let metrics_text = String::from_utf8_lossy(&metrics);
    assert!(
        metrics_text.starts_with("HTTP/1.1 200"),
        "the relay must still answer /metrics cleanly after the fuzz barrage; got {metrics_text:?}"
    );
    assert!(
        !metrics_text.contains("127.0.0.1") && !metrics_text.contains("PROBE-"),
        "/metrics must never expose the caller's IP or reflect fuzzed request content"
    );

    main_server.abort();
    metrics_server.abort();
}
