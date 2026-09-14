//! Integration tests for the routing-handle codec and the pairing URI, asserting the
//! codecs reject every malformed input in the `docs/11-relay-protocol.md` §9.5 table
//! that applies to `h` and to URI structure (`docs/90-implementation-plan.md` §5.2,
//! R-40-031).

use herdr_relay_proto::handle::{Handle, HandleError, PairingUri, PairingUriError};

#[cfg(feature = "generate")]
#[test]
fn handle_round_trips_through_generate_encode_and_parse() {
    let handle = Handle::generate().expect("system random source is available in tests");
    let encoded = handle.encode();
    assert_eq!(encoded.len(), 22);
    let decoded: Handle = encoded.parse().expect("a freshly encoded handle parses");
    assert_eq!(decoded, handle);
}

#[test]
fn handle_malformed_wrong_length_is_rejected() {
    // handle_malformed: not 22 unpadded base64url characters.
    let error = "abc"
        .parse::<Handle>()
        .expect_err("must reject a short handle");
    assert!(matches!(error, HandleError::WrongLength));
}

#[test]
fn handle_malformed_invalid_alphabet_is_rejected() {
    // handle_malformed: does not decode to 16 bytes because '+' and '/' are outside
    // the base64url (not base64) alphabet.
    let candidate = "++++++++++++++++++++++";
    assert_eq!(candidate.len(), 22);
    let error = candidate
        .parse::<Handle>()
        .expect_err("must reject standard-alphabet base64");
    assert!(matches!(error, HandleError::Decode(_)));
}

fn valid_uri() -> String {
    "herdr-remote://pair?v=1&r=https%3A%2F%2Frelay.example.com&h=n6Loxf94CfyIO6hOxlaHvA&p=remedy-tapestry-hubcap-oversleep-jailbird-kinetic".to_owned()
}

#[test]
fn pairing_uri_valid_worked_example_parses() {
    PairingUri::parse(&valid_uri()).expect("the worked example must parse");
}

#[test]
fn pairing_uri_pair_uri_scheme_is_rejected() {
    let uri = valid_uri().replacen("herdr-remote", "https", 1);
    let error = PairingUri::parse(&uri).expect_err("must reject a non-herdr-remote scheme");
    assert!(matches!(error, PairingUriError::Scheme));
    assert_eq!(error.code(), "pair_uri_scheme");
}

#[test]
fn pairing_uri_pair_uri_path_is_rejected() {
    let uri = valid_uri().replacen("pair?", "unpair?", 1);
    let error = PairingUri::parse(&uri).expect_err("must reject a non-pair path");
    assert!(matches!(error, PairingUriError::Path));
    assert_eq!(error.code(), "pair_uri_path");
}

#[test]
fn pairing_uri_pair_uri_version_absent_is_rejected() {
    let uri = valid_uri().replacen("v=1&", "", 1);
    let error = PairingUri::parse(&uri).expect_err("must reject a missing v field");
    assert!(matches!(error, PairingUriError::Version));
    assert_eq!(error.code(), "pair_uri_version");
}

#[test]
fn pairing_uri_pair_uri_version_wrong_is_rejected() {
    let uri = valid_uri().replacen("v=1", "v=2", 1);
    let error = PairingUri::parse(&uri).expect_err("must reject a v other than 1");
    assert!(matches!(error, PairingUriError::Version));
}

#[test]
fn pairing_uri_pair_uri_field_missing_is_rejected() {
    let uri = valid_uri().replacen(
        "&p=remedy-tapestry-hubcap-oversleep-jailbird-kinetic",
        "",
        1,
    );
    let error = PairingUri::parse(&uri).expect_err("must reject a missing p field");
    assert!(matches!(error, PairingUriError::FieldMissing));
    assert_eq!(error.code(), "pair_uri_field_missing");
}

#[test]
fn pairing_uri_pair_uri_field_repeated_is_rejected() {
    let uri = format!("{}&v=1", valid_uri());
    let error = PairingUri::parse(&uri).expect_err("must reject a repeated v field");
    assert!(matches!(error, PairingUriError::FieldRepeated));
    assert_eq!(error.code(), "pair_uri_field_repeated");
}

#[test]
fn pairing_uri_pair_uri_too_long_is_rejected() {
    let padding = "a".repeat(600);
    let uri = format!("{}&extra={padding}", valid_uri());
    let error = PairingUri::parse(&uri).expect_err("must reject a URI over 512 bytes");
    assert!(matches!(error, PairingUriError::TooLong));
    assert_eq!(error.code(), "pair_uri_too_long");
}

#[test]
fn pairing_uri_relay_origin_invalid_missing_scheme_is_rejected() {
    let uri = valid_uri().replacen(
        "r=https%3A%2F%2Frelay.example.com",
        "r=relay.example.com",
        1,
    );
    let error = PairingUri::parse(&uri).expect_err("must reject a schemeless origin");
    assert!(matches!(error, PairingUriError::RelayOriginInvalid));
    assert_eq!(error.code(), "relay_origin_invalid");
}

#[test]
fn pairing_uri_relay_origin_invalid_with_path_is_rejected() {
    let uri = valid_uri().replacen(
        "r=https%3A%2F%2Frelay.example.com",
        "r=https%3A%2F%2Frelay.example.com%2Fextra",
        1,
    );
    let error = PairingUri::parse(&uri).expect_err("must reject an origin carrying a path");
    assert!(matches!(error, PairingUriError::RelayOriginInvalid));
}

#[test]
fn pairing_uri_handle_malformed_is_rejected() {
    let uri = valid_uri().replacen("h=n6Loxf94CfyIO6hOxlaHvA", "h=tooshort", 1);
    let error = PairingUri::parse(&uri).expect_err("must reject a malformed handle");
    assert!(matches!(error, PairingUriError::HandleMalformed(_)));
    assert_eq!(error.code(), "handle_malformed");
}
