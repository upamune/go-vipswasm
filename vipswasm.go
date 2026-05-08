package vipswasm

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"image/draw"
	"image/jpeg"
	"image/png"
	"io"
	"math"
	"strings"
	"sync"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"

	"github.com/upamune/go-vipswasm/internal"
)

var (
	ErrClosed          = errors.New("vipswasm: engine is closed")
	ErrInvalidImage    = errors.New("vipswasm: invalid image")
	ErrInvalidGeometry = errors.New("vipswasm: invalid geometry")
	ErrTooLarge        = errors.New("vipswasm: image is too large")
)

// Version reports the libvips-compatible ABI version exposed by the wasm core.
type Version struct {
	Major int
	Minor int
	Micro int
}

// Engine owns one WebAssembly runtime instance and serializes calls into it.
type Engine struct {
	ctx     context.Context
	runtime wazero.Runtime
	module  api.Module
	alloc   api.Function
	free    api.Function
	mu      sync.Mutex
	closed  bool
}

// Image stores tightly packed RGBA pixels.
type Image struct {
	Pix    []byte
	Width  int
	Height int
}

// JPEGOptions configures EncodeJPEG.
type JPEGOptions struct {
	Quality int
}

// EncodeOptions configures Engine.EncodeImage.
type EncodeOptions struct {
	Quality int
}

// VipsOperation describes a generated libvips operation entry exposed by this package.
type VipsOperation struct {
	Name     string
	Nick     string
	Category string
	Inputs   []string
	Outputs  []string
}

// GeneratedOperations is the typed operation catalog used to keep the Go API
// aligned with libvips metadata in the style of cshum/vipsgen.
var GeneratedOperations = []VipsOperation{
	{
		Name:     "extract_area",
		Nick:     "extract an area from an image",
		Category: "conversion",
		Inputs:   []string{"in", "left", "top", "width", "height"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "resize",
		Nick:     "resize an image",
		Category: "resample",
		Inputs:   []string{"in", "scale", "vscale", "kernel"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "thumbnail",
		Nick:     "thumbnail an image",
		Category: "resample",
		Inputs:   []string{"filename", "width", "height"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "autorot",
		Nick:     "autorotate an image",
		Category: "conversion",
		Inputs:   []string{"in"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "jpegload",
		Nick:     "load JPEG from a source",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "jpegsave",
		Nick:     "save image as JPEG",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
	{
		Name:     "pngload",
		Nick:     "load PNG from a source",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "pngsave",
		Nick:     "save image as PNG",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
	{
		Name:     "heifload",
		Nick:     "load a HEIF image",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "heifsave",
		Nick:     "save image in HEIF format",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
	{
		Name:     "webpload",
		Nick:     "load WebP from a source",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "webpsave",
		Nick:     "save image as WebP",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
	{
		Name:     "tiffload",
		Nick:     "load TIFF from a source",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "tiffsave",
		Nick:     "save image as TIFF",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
	{
		Name:     "gifload",
		Nick:     "load GIF from a source",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "gifsave",
		Nick:     "save image as GIF",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
	{
		Name:     "jxlload",
		Nick:     "load JPEG XL from a source",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "jxlsave",
		Nick:     "save image as JPEG XL",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
	{
		Name:     "jp2kload",
		Nick:     "load JPEG 2000 from a source",
		Category: "foreign",
		Inputs:   []string{"source"},
		Outputs:  []string{"out"},
	},
	{
		Name:     "jp2ksave",
		Nick:     "save image as JPEG 2000",
		Category: "foreign",
		Inputs:   []string{"in", "target"},
		Outputs:  nil,
	},
}

// New starts an Engine backed by the embedded WebAssembly core.
func New(ctx context.Context) (*Engine, error) {
	return NewWithWasm(ctx, internal.Wasm)
}

// NewFull starts an Engine backed by the larger full-format WebAssembly core.
func NewFull(ctx context.Context) (*Engine, error) {
	return NewWithWasm(ctx, internal.FullWasm)
}

// NewWithWasm starts an Engine backed by caller-supplied WebAssembly bytes.
func NewWithWasm(ctx context.Context, wasm []byte) (*Engine, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if len(wasm) == 0 {
		return nil, errors.New("vipswasm: empty wasm core")
	}

	rt := wazero.NewRuntime(ctx)
	if _, err := wasi_snapshot_preview1.Instantiate(ctx, rt); err != nil {
		_ = rt.Close(ctx)
		return nil, err
	}
	if _, err := rt.NewHostModuleBuilder("env").
		NewFunctionBuilder().WithFunc(func(context.Context, uint32) uint32 {
		return 0
	}).Export("__cxa_begin_catch").
		NewFunctionBuilder().WithFunc(func(context.Context, uint32) uint32 {
		return 0
	}).Export("__cxa_allocate_exception").
		NewFunctionBuilder().WithFunc(func(context.Context, uint32, uint32, uint32) {
		panic("vipswasm: wasm C++ exception thrown")
	}).Export("__cxa_throw").
		Instantiate(ctx); err != nil {
		_ = rt.Close(ctx)
		return nil, err
	}

	mod, err := rt.Instantiate(ctx, wasm)
	if err != nil {
		_ = rt.Close(ctx)
		return nil, err
	}

	e := &Engine{
		ctx:     ctx,
		runtime: rt,
		module:  mod,
		alloc:   mod.ExportedFunction("wasm_alloc"),
		free:    mod.ExportedFunction("wasm_free"),
	}
	if e.alloc == nil || e.free == nil {
		_ = e.Close()
		return nil, errors.New("vipswasm: wasm core is missing wasmify allocator exports")
	}
	if init := mod.ExportedFunction("_initialize"); init != nil {
		if _, err := init.Call(ctx); err != nil {
			_ = e.Close()
			return nil, err
		}
	}
	if init := mod.ExportedFunction("wasm_init"); init != nil {
		if _, err := init.Call(ctx); err != nil {
			_ = e.Close()
			return nil, err
		}
	}
	return e, nil
}

// Close releases the underlying WebAssembly runtime.
func (e *Engine) Close() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return nil
	}
	if shutdown := e.module.ExportedFunction("wasm_shutdown"); shutdown != nil {
		_, _ = shutdown.Call(e.ctx)
	}
	e.closed = true
	return e.runtime.Close(e.ctx)
}

// Version returns the ABI version reported by the embedded core.
func (e *Engine) Version() (Version, error) {
	resp, err := e.invokeWasmify("w_0_2", nil)
	if err != nil {
		return Version{}, err
	}
	v := pbReadUint32Field(resp, 1)
	return Version{Major: int(v >> 16), Minor: int((v >> 8) & 0xff), Micro: int(v & 0xff)}, nil
}

// NewImageFromRGBA converts any Go image into a tightly packed RGBA Image.
func NewImageFromRGBA(src image.Image) (*Image, error) {
	if src == nil {
		return nil, ErrInvalidImage
	}
	bounds := src.Bounds()
	if bounds.Empty() {
		return nil, ErrInvalidImage
	}
	if _, err := rgbaLen(bounds.Dx(), bounds.Dy()); err != nil {
		return nil, err
	}
	rgba := image.NewRGBA(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	draw.Draw(rgba, rgba.Bounds(), src, bounds.Min, draw.Src)
	return &Image{
		Pix:    append([]byte(nil), rgba.Pix...),
		Width:  rgba.Rect.Dx(),
		Height: rgba.Rect.Dy(),
	}, nil
}

// NewImageFromRawRGBA copies a tightly packed RGBA buffer into an Image.
func NewImageFromRawRGBA(pix []byte, width, height int) (*Image, error) {
	n, err := rgbaLen(width, height)
	if err != nil {
		return nil, err
	}
	if len(pix) != n {
		return nil, ErrInvalidImage
	}
	return &Image{Pix: append([]byte(nil), pix...), Width: width, Height: height}, nil
}

// Decode decodes an image with Go's registered image decoders and converts it to RGBA.
func Decode(r io.Reader) (*Image, string, error) {
	src, format, err := image.Decode(r)
	if err != nil {
		return nil, "", err
	}
	img, err := NewImageFromRGBA(src)
	if err != nil {
		return nil, "", err
	}
	return img, format, nil
}

// DecodeImage decodes image bytes through the embedded libvips foreign loader.
func (e *Engine) DecodeImage(data []byte) (*Image, error) {
	return e.decodeRGBA("vipswasm_load_rgba", data)
}

// DecodePNG decodes PNG bytes through the embedded libvips PNG loader.
func (e *Engine) DecodePNG(data []byte) (*Image, error) {
	return e.decodeRGBA("vipswasm_pngload_rgba", data)
}

func (e *Engine) decodeRGBA(export string, data []byte) (*Image, error) {
	if len(data) == 0 {
		return nil, ErrInvalidImage
	}

	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return nil, ErrClosed
	}
	fn := e.module.ExportedFunction(export)
	if fn == nil {
		return nil, fmt.Errorf("vipswasm: wasm core is missing %s export", export)
	}
	srcPtr, err := e.allocBytes(data)
	if err != nil {
		return nil, err
	}
	defer e.freePtr(srcPtr)
	metaPtr, err := e.allocBytes(make([]byte, 16))
	if err != nil {
		return nil, err
	}
	defer e.freePtr(metaPtr)

	ret, err := fn.Call(e.ctx, uint64(srcPtr), uint64(len(data)), uint64(metaPtr), uint64(metaPtr+4), uint64(metaPtr+8), uint64(metaPtr+12))
	if err != nil {
		return nil, err
	}
	if int32(ret[0]) != 0 {
		return nil, ErrInvalidImage
	}
	meta, ok := e.module.Memory().Read(metaPtr, 16)
	if !ok {
		return nil, errors.New("vipswasm: failed to read PNG decode metadata")
	}
	outPtr := binary.LittleEndian.Uint32(meta[0:4])
	outLen := binary.LittleEndian.Uint32(meta[4:8])
	width := int(binary.LittleEndian.Uint32(meta[8:12]))
	height := int(binary.LittleEndian.Uint32(meta[12:16]))
	defer e.freePtr(outPtr)
	if want, err := rgbaLen(width, height); err != nil || want != int(outLen) {
		return nil, ErrInvalidImage
	}
	pix, ok := e.module.Memory().Read(outPtr, outLen)
	if !ok {
		return nil, errors.New("vipswasm: failed to read PNG decode output")
	}
	return &Image{Pix: append([]byte(nil), pix...), Width: width, Height: height}, nil
}

// EncodeImage encodes an image in the requested format. PNG and JPEG use the
// same Go encoders as EncodePNG and EncodeJPEG; other formats use the embedded
// libvips foreign saver when the wasm core supports it.
func (e *Engine) EncodeImage(img *Image, format string, opts *EncodeOptions) ([]byte, error) {
	if err := img.validate(); err != nil {
		return nil, err
	}
	switch normalizeFormat(format) {
	case "png":
		var out bytes.Buffer
		if err := img.EncodePNG(&out); err != nil {
			return nil, err
		}
		return out.Bytes(), nil
	case "jpeg":
		var out bytes.Buffer
		quality := 0
		if opts != nil {
			quality = opts.Quality
		}
		if err := img.EncodeJPEG(&out, &JPEGOptions{Quality: quality}); err != nil {
			return nil, err
		}
		return out.Bytes(), nil
	}
	suffix, err := libvipsSaveSuffix(format, opts)
	if err != nil {
		return nil, err
	}

	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return nil, ErrClosed
	}
	fn := e.module.ExportedFunction("vipswasm_save_rgba")
	if fn == nil {
		return nil, errors.New("vipswasm: wasm core is missing vipswasm_save_rgba export")
	}
	srcPtr, err := e.allocBytes(img.Pix)
	if err != nil {
		return nil, err
	}
	defer e.freePtr(srcPtr)
	suffixPtr, err := e.allocBytes([]byte(suffix))
	if err != nil {
		return nil, err
	}
	defer e.freePtr(suffixPtr)
	metaPtr, err := e.allocBytes(make([]byte, 8))
	if err != nil {
		return nil, err
	}
	defer e.freePtr(metaPtr)

	ret, err := fn.Call(e.ctx, uint64(srcPtr), uint64(img.Width), uint64(img.Height), uint64(suffixPtr), uint64(len(suffix)), uint64(metaPtr), uint64(metaPtr+4))
	if err != nil {
		return nil, err
	}
	if int32(ret[0]) != 0 {
		return nil, fmt.Errorf("vipswasm: failed to encode %s", format)
	}
	meta, ok := e.module.Memory().Read(metaPtr, 8)
	if !ok {
		return nil, errors.New("vipswasm: failed to read encode metadata")
	}
	outPtr := binary.LittleEndian.Uint32(meta[0:4])
	outLen := binary.LittleEndian.Uint32(meta[4:8])
	defer e.freePtr(outPtr)
	out, ok := e.module.Memory().Read(outPtr, outLen)
	if !ok {
		return nil, errors.New("vipswasm: failed to read encode output")
	}
	return append([]byte(nil), out...), nil
}

// EncodePNG writes the image as PNG.
func (img *Image) EncodePNG(w io.Writer) error {
	rgba, err := img.ToRGBA()
	if err != nil {
		return err
	}
	return png.Encode(w, rgba)
}

// EncodeJPEG writes the image as JPEG.
func (img *Image) EncodeJPEG(w io.Writer, opts *JPEGOptions) error {
	rgba, err := img.ToRGBA()
	if err != nil {
		return err
	}
	quality := 90
	if opts != nil && opts.Quality != 0 {
		quality = opts.Quality
	}
	if quality < 1 || quality > 100 {
		return ErrInvalidGeometry
	}
	return jpeg.Encode(w, rgba, &jpeg.Options{Quality: quality})
}

func libvipsSaveSuffix(format string, opts *EncodeOptions) (string, error) {
	format = normalizeFormat(format)
	if format == "" {
		return "", ErrInvalidImage
	}
	suffix := "." + format
	if format == "jpeg" {
		suffix = ".jpg"
	}
	quality := 0
	if opts != nil {
		quality = opts.Quality
	}
	if quality == 0 {
		return suffix, nil
	}
	if quality < 1 || quality > 100 {
		return "", ErrInvalidGeometry
	}
	switch format {
	case "jpeg", "webp", "heif", "heic", "avif", "jxl", "jp2", "j2k":
		return fmt.Sprintf("%s[Q=%d]", suffix, quality), nil
	default:
		return suffix, nil
	}
}

func normalizeFormat(format string) string {
	format = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(format, ".")))
	switch format {
	case "jpg":
		return "jpeg"
	case "tif":
		return "tiff"
	case "j2c", "j2k":
		return "jp2"
	default:
		return format
	}
}

// ToRGBA copies the image into image.RGBA.
func (img *Image) ToRGBA() (*image.RGBA, error) {
	if err := img.validate(); err != nil {
		return nil, err
	}
	out := image.NewRGBA(image.Rect(0, 0, img.Width, img.Height))
	copy(out.Pix, img.Pix)
	return out, nil
}

// ResizeNearest resizes an image with nearest-neighbor sampling in WebAssembly.
func (e *Engine) ResizeNearest(img *Image, width, height int) (*Image, error) {
	if err := img.validate(); err != nil {
		return nil, err
	}
	if width <= 0 || height <= 0 {
		return nil, ErrInvalidGeometry
	}
	if _, err := rgbaLen(width, height); err != nil {
		return nil, err
	}
	req := pbAppendString(nil, 1, string(img.Pix))
	req = pbAppendUint32(req, 2, uint32(img.Width))
	req = pbAppendUint32(req, 3, uint32(img.Height))
	req = pbAppendUint32(req, 4, uint32(width))
	req = pbAppendUint32(req, 5, uint32(height))
	return e.imageOp("w_0_1", width, height, req)
}

// ExtractArea crops an image in WebAssembly.
func (e *Engine) ExtractArea(img *Image, left, top, width, height int) (*Image, error) {
	if err := img.validate(); err != nil {
		return nil, err
	}
	if left < 0 || top < 0 || width <= 0 || height <= 0 || left+width > img.Width || top+height > img.Height {
		return nil, ErrInvalidGeometry
	}
	if _, err := rgbaLen(width, height); err != nil {
		return nil, err
	}
	req := pbAppendString(nil, 1, string(img.Pix))
	req = pbAppendUint32(req, 2, uint32(img.Width))
	req = pbAppendUint32(req, 3, uint32(img.Height))
	req = pbAppendUint32(req, 4, uint32(left))
	req = pbAppendUint32(req, 5, uint32(top))
	req = pbAppendUint32(req, 6, uint32(width))
	req = pbAppendUint32(req, 7, uint32(height))
	return e.imageOp("w_0_0", width, height, req)
}

func (e *Engine) imageOp(name string, width, height int, req []byte) (*Image, error) {
	outLen, err := rgbaLen(width, height)
	if err != nil {
		return nil, err
	}
	resp, err := e.invokeWasmify(name, req)
	if err != nil {
		return nil, err
	}
	out := []byte(pbReadStringField(resp, 1))
	if len(out) != outLen {
		return nil, ErrInvalidGeometry
	}
	return &Image{Pix: out, Width: width, Height: height}, nil
}

func (e *Engine) invokeWasmify(name string, req []byte) ([]byte, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return nil, ErrClosed
	}
	fn := e.module.ExportedFunction(name)
	if fn == nil {
		return nil, fmt.Errorf("vipswasm: wasm core is missing %s export", name)
	}
	reqPtr, err := e.allocBytes(req)
	if err != nil {
		return nil, err
	}
	defer e.freePtr(reqPtr)
	out, err := fn.Call(e.ctx, uint64(reqPtr), uint64(len(req)))
	if err != nil {
		return nil, err
	}
	packed := out[0]
	respPtr := uint32(packed >> 32)
	respLen := uint32(packed)
	if respPtr == 0 && respLen != 0 {
		return nil, errors.New("vipswasm: wasmify response allocation failed")
	}
	defer e.freePtr(respPtr)
	resp, ok := e.module.Memory().Read(respPtr, respLen)
	if !ok {
		return nil, errors.New("vipswasm: failed to read wasmify response")
	}
	return append([]byte(nil), resp...), pbExtractError(resp)
}

func (e *Engine) allocBytes(data []byte) (uint32, error) {
	out, err := e.alloc.Call(e.ctx, uint64(len(data)))
	if err != nil {
		return 0, err
	}
	ptr := uint32(out[0])
	if ptr == 0 && len(data) != 0 {
		return 0, errors.New("vipswasm: wasm allocation failed")
	}
	if len(data) > 0 && !e.module.Memory().Write(ptr, data) {
		e.freePtr(ptr)
		return 0, errors.New("vipswasm: failed to write wasm memory")
	}
	return ptr, nil
}

func (e *Engine) freePtr(ptr uint32) {
	_, _ = e.free.Call(e.ctx, uint64(ptr))
}

func (img *Image) validate() error {
	if img == nil {
		return ErrInvalidImage
	}
	n, err := rgbaLen(img.Width, img.Height)
	if err != nil {
		return err
	}
	if len(img.Pix) != n {
		return ErrInvalidImage
	}
	return nil
}

func rgbaLen(width, height int) (int, error) {
	if width <= 0 || height <= 0 {
		return 0, ErrInvalidGeometry
	}
	if width > math.MaxInt/height || width*height > math.MaxInt/4 {
		return 0, ErrTooLarge
	}
	return width * height * 4, nil
}

func pbAppendUint32(buf []byte, field uint32, v uint32) []byte {
	buf = pbAppendTag(buf, field, 0)
	return pbAppendVarint(buf, uint64(v))
}

func pbAppendString(buf []byte, field uint32, s string) []byte {
	buf = pbAppendTag(buf, field, 2)
	buf = pbAppendVarint(buf, uint64(len(s)))
	return append(buf, s...)
}

func pbAppendTag(buf []byte, field, wireType uint32) []byte {
	return pbAppendVarint(buf, uint64(field<<3|wireType))
}

func pbAppendVarint(buf []byte, v uint64) []byte {
	for v >= 0x80 {
		buf = append(buf, byte(v)|0x80)
		v >>= 7
	}
	return append(buf, byte(v))
}

func pbExtractError(data []byte) error {
	if msg := pbReadStringField(data, 15); msg != "" {
		return errors.New(msg)
	}
	return nil
}

func pbReadStringField(data []byte, wantField uint32) string {
	for pos := 0; pos < len(data); {
		tag, n := pbReadVarint(data[pos:])
		pos += n
		field, wireType := uint32(tag>>3), uint32(tag&7)
		if wireType != 2 {
			pos = pbSkip(data, pos, wireType)
			continue
		}
		size, n := pbReadVarint(data[pos:])
		pos += n
		end := pos + int(size)
		if end > len(data) {
			return ""
		}
		if field == wantField {
			return string(data[pos:end])
		}
		pos = end
	}
	return ""
}

func pbReadUint32Field(data []byte, wantField uint32) uint32 {
	for pos := 0; pos < len(data); {
		tag, n := pbReadVarint(data[pos:])
		pos += n
		field, wireType := uint32(tag>>3), uint32(tag&7)
		if wireType != 0 {
			pos = pbSkip(data, pos, wireType)
			continue
		}
		v, n := pbReadVarint(data[pos:])
		pos += n
		if field == wantField {
			return uint32(v)
		}
	}
	return 0
}

func pbReadVarint(data []byte) (uint64, int) {
	var v uint64
	for i, b := range data {
		v |= uint64(b&0x7f) << (7 * i)
		if b < 0x80 {
			return v, i + 1
		}
	}
	return v, len(data)
}

func pbSkip(data []byte, pos int, wireType uint32) int {
	switch wireType {
	case 0:
		_, n := pbReadVarint(data[pos:])
		return pos + n
	case 1:
		return pos + 8
	case 2:
		size, n := pbReadVarint(data[pos:])
		return pos + n + int(size)
	case 5:
		return pos + 4
	default:
		return len(data)
	}
}
