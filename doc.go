// Package vipswasm provides a CGO-free image processing runtime backed by an
// embedded WebAssembly core.
//
// The public Go API owns the wazero runtime, feeds RGBA buffers through the
// wasmify-generated bridge exports, and never loads host dynamic libraries.
package vipswasm
