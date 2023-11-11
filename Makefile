.PHONY: test-rust
test-rust:
	cd Rust && cargo test && cargo build --release
	gcc C/test/main.c -IC/ Rust/target/release/deps/libhello.so
	./a.out

