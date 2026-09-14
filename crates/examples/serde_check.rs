use serde::Serialize;

#[derive(Serialize)]
struct Foo {
    a: String,
    b: Option<String>,
}

fn main() {
    let foo = Foo { a: "x".to_string(), b: None };
    println!("{}", serde_json::to_string(&foo).unwrap());
}
