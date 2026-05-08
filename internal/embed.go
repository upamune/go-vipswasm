package internal

import _ "embed"

//go:embed vipswasm.wasm
var Wasm []byte

//go:embed vipswasm_full.wasm
var FullWasm []byte
