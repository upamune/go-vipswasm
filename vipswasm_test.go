package vipswasm

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/color"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"testing"
)

func TestEngineVersion(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	got, err := e.Version()
	if err != nil {
		t.Fatalf("Version() error = %v", err)
	}
	if got.Major != 8 || got.Minor != 18 {
		t.Fatalf("Version() = %+v, want libvips-compatible 8.18.x core", got)
	}
}

func TestNewEngineVersion(t *testing.T) {
	e, err := New(context.Background())
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	defer e.Close()

	got, err := e.Version()
	if err != nil {
		t.Fatalf("Version() error = %v", err)
	}
	if got.Major != 8 || got.Minor != 18 {
		t.Fatalf("Version() = %+v, want libvips-compatible 8.18.x core", got)
	}
}

func TestResizeNearest(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	src := image.NewRGBA(image.Rect(0, 0, 2, 2))
	src.SetRGBA(0, 0, color.RGBA{R: 255, A: 255})
	src.SetRGBA(1, 0, color.RGBA{G: 255, A: 255})
	src.SetRGBA(0, 1, color.RGBA{B: 255, A: 255})
	src.SetRGBA(1, 1, color.RGBA{R: 255, G: 255, A: 255})

	img, err := NewImageFromRGBA(src)
	if err != nil {
		t.Fatalf("NewImageFromRGBA() error = %v", err)
	}
	got, err := e.ResizeNearest(img, 4, 4)
	if err != nil {
		t.Fatalf("ResizeNearest() error = %v", err)
	}
	out, err := got.ToRGBA()
	if err != nil {
		t.Fatalf("ToRGBA() error = %v", err)
	}

	assertRGBA(t, out, 0, 0, color.RGBA{R: 255, A: 255})
	assertRGBA(t, out, 2, 0, color.RGBA{G: 255, A: 255})
	assertRGBA(t, out, 0, 2, color.RGBA{B: 255, A: 255})
	assertRGBA(t, out, 2, 2, color.RGBA{R: 255, G: 255, A: 255})
}

func TestWrapWasmMemoryLimit(t *testing.T) {
	for _, msg := range []string{
		"wasm error: out of bounds memory access",
		"memory grow failed: limit exceeded",
		"memory minimum size exceeds limit",
	} {
		err := wrapWasmError(errors.New(msg))
		if !errors.Is(err, ErrWasmMemoryLimit) {
			t.Fatalf("wrapWasmError(%q) = %v, want ErrWasmMemoryLimit", msg, err)
		}
	}
}

func TestOptionsPolicyLimits(t *testing.T) {
	e, err := NewWithOptions(context.Background(), Options{MaxInputBytes: 1, MaxOutputPixels: 1})
	if err != nil {
		t.Fatalf("NewWithOptions() error = %v", err)
	}
	defer e.Close()
	if _, err := e.DecodeImage([]byte{1, 2}); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("DecodeImage over MaxInputBytes error = %v, want ErrTooLarge", err)
	}
	img, err := NewImageFromRawRGBA([]byte{0, 0, 0, 255}, 1, 1)
	if err != nil {
		t.Fatalf("NewImageFromRawRGBA() error = %v", err)
	}
	if _, err := e.ResizeNearest(img, 2, 1); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("ResizeNearest over MaxOutputPixels error = %v, want ErrTooLarge", err)
	}
}

func TestSupportedFormatsIncludesHEIC(t *testing.T) {
	var heic *FormatSupport
	for _, fs := range SupportedFormats() {
		fs := fs
		if fs.Format == "heic" {
			heic = &fs
			break
		}
	}
	if heic == nil {
		t.Fatalf("SupportedFormats() missing heic")
	}
	if !heic.Decode || heic.Encode || !heic.DecodeTimeResize {
		t.Fatalf("heic support = %+v, want decode-only support with decode-time resize", *heic)
	}
}

func TestSupportedFormatsIncludesJPEGEncode(t *testing.T) {
	var jpeg *FormatSupport
	for _, fs := range SupportedFormats() {
		fs := fs
		if fs.Format == "jpeg" {
			jpeg = &fs
			break
		}
	}
	if jpeg == nil {
		t.Fatalf("SupportedFormats() missing jpeg")
	}
	if !jpeg.Decode || !jpeg.Encode || !jpeg.DecodeTimeResize {
		t.Fatalf("jpeg support = %+v, want decode and encode support with decode-time resize", *jpeg)
	}
}

func TestExtractArea(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	src := image.NewRGBA(image.Rect(0, 0, 3, 2))
	src.SetRGBA(1, 0, color.RGBA{R: 10, G: 20, B: 30, A: 255})
	src.SetRGBA(2, 0, color.RGBA{R: 40, G: 50, B: 60, A: 255})
	src.SetRGBA(1, 1, color.RGBA{R: 70, G: 80, B: 90, A: 255})
	src.SetRGBA(2, 1, color.RGBA{R: 100, G: 110, B: 120, A: 255})

	img, err := NewImageFromRGBA(src)
	if err != nil {
		t.Fatalf("NewImageFromRGBA() error = %v", err)
	}
	got, err := e.ExtractArea(img, 1, 0, 2, 2)
	if err != nil {
		t.Fatalf("ExtractArea() error = %v", err)
	}
	if got.Width != 2 || got.Height != 2 {
		t.Fatalf("ExtractArea() size = %dx%d, want 2x2", got.Width, got.Height)
	}
	out, err := got.ToRGBA()
	if err != nil {
		t.Fatalf("ToRGBA() error = %v", err)
	}

	assertRGBA(t, out, 0, 0, color.RGBA{R: 10, G: 20, B: 30, A: 255})
	assertRGBA(t, out, 1, 0, color.RGBA{R: 40, G: 50, B: 60, A: 255})
	assertRGBA(t, out, 0, 1, color.RGBA{R: 70, G: 80, B: 90, A: 255})
	assertRGBA(t, out, 1, 1, color.RGBA{R: 100, G: 110, B: 120, A: 255})
}

func TestLibvipsDecodeAndEncodePNG(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	src := image.NewRGBA(image.Rect(0, 0, 2, 1))
	src.SetRGBA(0, 0, color.RGBA{R: 1, G: 2, B: 3, A: 255})
	src.SetRGBA(1, 0, color.RGBA{R: 4, G: 5, B: 6, A: 255})

	img, err := NewImageFromRGBA(src)
	if err != nil {
		t.Fatalf("NewImageFromRGBA() error = %v", err)
	}
	encoded, err := e.EncodeImage(img, "png", nil)
	if err != nil {
		t.Fatalf("Engine.EncodeImage(png) error = %v", err)
	}
	got, err := e.DecodePNG(encoded)
	if err != nil {
		t.Fatalf("Engine.DecodePNG() error = %v", err)
	}
	out, err := got.ToRGBA()
	if err != nil {
		t.Fatalf("ToRGBA() error = %v", err)
	}
	assertRGBA(t, out, 0, 0, color.RGBA{R: 1, G: 2, B: 3, A: 255})
	assertRGBA(t, out, 1, 0, color.RGBA{R: 4, G: 5, B: 6, A: 255})

	generic, err := e.DecodeImage(encoded)
	if err != nil {
		t.Fatalf("Engine.DecodeImage() error = %v", err)
	}
	if generic.Width != 2 || generic.Height != 1 {
		t.Fatalf("Engine.DecodeImage() size = %dx%d, want 2x1", generic.Width, generic.Height)
	}

	if e.module.ExportedFunction("vipswasm_load_thumbnail_rgba") != nil {
		thumb, err := e.DecodeImageWithOptions(encoded, &DecodeOptions{ResizeWidth: 1, ResizeHeight: 1})
		if err != nil {
			t.Fatalf("Engine.DecodeImageWithOptions() error = %v", err)
		}
		if thumb.Width != 1 || thumb.Height != 1 {
			t.Fatalf("Engine.DecodeImageWithOptions() size = %dx%d, want 1x1", thumb.Width, thumb.Height)
		}
	} else {
		if _, err := e.DecodeImageWithOptions(encoded, &DecodeOptions{ResizeWidth: 1, ResizeHeight: 1}); err == nil || !strings.Contains(err.Error(), "vipswasm_load_thumbnail_rgba") {
			t.Fatalf("Engine.DecodeImageWithOptions() missing export error = %v, want missing thumbnail export", err)
		}
	}

	encodedPNG, err := e.EncodeImage(img, "png", nil)
	if err != nil {
		t.Fatalf("Engine.EncodeImage(png) error = %v", err)
	}
	if len(encodedPNG) < 8 || string(encodedPNG[:8]) != "\x89PNG\r\n\x1a\n" {
		t.Fatalf("Engine.EncodeImage(png) did not return PNG")
	}
	encodedRaw, err := e.EncodeImage(img, "raw", nil)
	if err != nil {
		t.Fatalf("Engine.EncodeImage(raw) error = %v", err)
	}
	if !bytes.Equal(encodedRaw, img.Pix) {
		t.Fatalf("Engine.EncodeImage(raw) = %v, want %v", encodedRaw, img.Pix)
	}

	encodedWebP, err := e.EncodeImage(img, "webp", nil)
	if err != nil {
		t.Fatalf("Engine.EncodeImage(webp) error = %v", err)
	}
	if !isWebP(encodedWebP) {
		t.Fatalf("Engine.EncodeImage(webp) did not return WebP")
	}

	encodedJPEG, err := e.EncodeImage(img, "jpeg", &EncodeOptions{Quality: 90})
	if err != nil {
		t.Fatalf("Engine.EncodeImage(jpeg) error = %v", err)
	}
	if !isJPEG(encodedJPEG) {
		t.Fatalf("Engine.EncodeImage(jpeg) did not return JPEG")
	}
	decodedJPEG, err := e.DecodeImage(encodedJPEG)
	if err != nil {
		t.Fatalf("Engine.DecodeImage(jpeg) error = %v", err)
	}
	if decodedJPEG.Width != img.Width || decodedJPEG.Height != img.Height {
		t.Fatalf("Engine.DecodeImage(jpeg) size = %dx%d, want %dx%d", decodedJPEG.Width, decodedJPEG.Height, img.Width, img.Height)
	}

	encodedTIFF, err := e.EncodeImage(img, "tiff", nil)
	if err != nil {
		t.Fatalf("Engine.EncodeImage(tiff) error = %v", err)
	}
	if !isTIFF(encodedTIFF) {
		t.Fatalf("Engine.EncodeImage(tiff) did not return TIFF")
	}

	if _, err := e.EncodeImage(img, "bmp", nil); !errors.Is(err, ErrUnsupportedFormat) {
		t.Fatalf("Engine.EncodeImage(bmp) error = %v, want ErrUnsupportedFormat", err)
	}
}

func TestMalformedJPEGDoesNotPoisonEngine(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	malformedJPEG := []byte{
		0xff, 0xd8,
		0xff, 0xdb, 0x00, 0x43, 0x00,
	}
	if _, err := e.DecodeImage(malformedJPEG); err == nil {
		t.Fatalf("Engine.DecodeImage(malformed jpeg) error = nil")
	}

	img, err := NewImageFromRawRGBA([]byte{
		255, 0, 0, 255,
		0, 255, 0, 255,
		0, 0, 255, 255,
		255, 255, 255, 255,
	}, 2, 2)
	if err != nil {
		t.Fatalf("NewImageFromRawRGBA error = %v", err)
	}
	encoded, err := e.EncodeImage(img, "jpeg", &EncodeOptions{Quality: 85})
	if err != nil {
		t.Fatalf("Engine.EncodeImage(jpeg) after malformed decode error = %v", err)
	}
	if !isJPEG(encoded) {
		t.Fatalf("Engine.EncodeImage(jpeg) after malformed decode did not return JPEG")
	}
	decoded, err := e.DecodeImage(encoded)
	if err != nil {
		t.Fatalf("Engine.DecodeImage(valid jpeg) after malformed decode error = %v", err)
	}
	if decoded.Width != img.Width || decoded.Height != img.Height {
		t.Fatalf("Engine.DecodeImage(valid jpeg) after malformed decode size = %dx%d, want %dx%d", decoded.Width, decoded.Height, img.Width, img.Height)
	}
}

func TestWasmTrapReinstantiatesEngine(t *testing.T) {
	trappingWasm := []byte{
		0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
		0x01, 0x14, 0x03, 0x60, 0x01, 0x7f, 0x01, 0x7f, 0x60, 0x01, 0x7f, 0x00, 0x60, 0x06, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x01, 0x7f,
		0x03, 0x04, 0x03, 0x00, 0x01, 0x02,
		0x05, 0x03, 0x01, 0x00, 0x01,
		0x07, 0x38, 0x04,
		0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
		0x0a, 0x77, 0x61, 0x73, 0x6d, 0x5f, 0x61, 0x6c, 0x6c, 0x6f, 0x63, 0x00, 0x00,
		0x09, 0x77, 0x61, 0x73, 0x6d, 0x5f, 0x66, 0x72, 0x65, 0x65, 0x00, 0x01,
		0x12, 0x76, 0x69, 0x70, 0x73, 0x77, 0x61, 0x73, 0x6d, 0x5f, 0x6c, 0x6f, 0x61, 0x64, 0x5f, 0x72, 0x67, 0x62, 0x61, 0x00, 0x02,
		0x0a, 0x0e, 0x03, 0x05, 0x00, 0x41, 0x80, 0x08, 0x0b, 0x02, 0x00, 0x0b, 0x03, 0x00, 0x00, 0x0b,
	}
	e, err := NewWithWasm(context.Background(), trappingWasm)
	if err != nil {
		t.Fatalf("NewWithWasm(trapping) error = %v", err)
	}
	defer e.Close()

	if _, err := e.DecodeImage([]byte{1}); err == nil {
		t.Fatalf("Engine.DecodeImage(trapping wasm) error = nil")
	} else if !errors.Is(err, ErrWasmTrap) {
		t.Fatalf("Engine.DecodeImage(trapping wasm) error = %v, want ErrWasmTrap", err)
	}
	if e.closed {
		t.Fatalf("Engine is closed after trapping call")
	}
	out, err := e.alloc.Call(e.ctx, 1)
	if err != nil {
		t.Fatalf("allocator after trapping call error = %v", err)
	}
	if got := uint32(out[0]); got != 1024 {
		t.Fatalf("allocator after trapping call = %d, want 1024", got)
	}
}

func TestEncodeImageAdditionalLibvipsSavers(t *testing.T) {
	e, err := New(context.Background())
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	defer e.Close()

	src := image.NewRGBA(image.Rect(0, 0, 4, 4))
	for y := 0; y < 4; y++ {
		for x := 0; x < 4; x++ {
			src.SetRGBA(x, y, color.RGBA{R: uint8(x * 40), G: uint8(y * 40), B: 120, A: 255})
		}
	}
	img, err := NewImageFromRGBA(src)
	if err != nil {
		t.Fatalf("NewImageFromRGBA() error = %v", err)
	}

	tests := []struct {
		format string
		valid  func([]byte) bool
	}{
		{format: "gif", valid: func(b []byte) bool { return len(b) >= 6 && (string(b[:6]) == "GIF87a" || string(b[:6]) == "GIF89a") }},
		{format: "jp2", valid: func(b []byte) bool { return len(b) >= 12 && string(b[4:12]) == "jP  \r\n\x87\n" }},
	}
	for _, tt := range tests {
		t.Run(tt.format, func(t *testing.T) {
			encoded, err := e.EncodeImage(img, tt.format, nil)
			if err != nil {
				t.Fatalf("Engine.EncodeImage(%s) error = %v", tt.format, err)
			}
			if !tt.valid(encoded) {
				t.Fatalf("Engine.EncodeImage(%s) returned unexpected header: % x", tt.format, encoded[:min(len(encoded), 16)])
			}
		})
	}
}

func TestGeneratedOperationCatalogCoversForeignCodecs(t *testing.T) {
	want := map[string]string{
		"extract_area": "conversion",
		"resize":       "resample",
		"thumbnail":    "resample",
		"autorot":      "conversion",
		"jpegload":     "foreign",
		"jpegsave":     "foreign",
		"pngload":      "foreign",
		"pngsave":      "foreign",
		"heifload":     "foreign",
		"heifsave":     "foreign",
		"webpload":     "foreign",
		"webpsave":     "foreign",
		"tiffload":     "foreign",
		"tiffsave":     "foreign",
		"gifload":      "foreign",
		"gifsave":      "foreign",
		"jxlload":      "foreign",
		"jxlsave":      "foreign",
		"jp2kload":     "foreign",
		"jp2ksave":     "foreign",
	}
	got := make(map[string]VipsOperation, len(GeneratedOperations))
	for _, op := range GeneratedOperations {
		got[op.Name] = op
	}
	for name, category := range want {
		op, ok := got[name]
		if !ok {
			t.Fatalf("GeneratedOperations missing %q", name)
		}
		if op.Category != category {
			t.Fatalf("GeneratedOperations[%q].Category = %q, want %q", name, op.Category, category)
		}
	}
}

func isTIFF(b []byte) bool {
	return len(b) >= 4 && (string(b[:4]) == "II*\x00" || string(b[:4]) == "MM\x00*")
}

func isWebP(b []byte) bool {
	return len(b) >= 12 && string(b[:4]) == "RIFF" && string(b[8:12]) == "WEBP"
}

func isJPEG(b []byte) bool {
	return len(b) >= 4 && b[0] == 0xff && b[1] == 0xd8 && b[len(b)-2] == 0xff && b[len(b)-1] == 0xd9
}

func TestNewImageFromRawRGBACopiesInput(t *testing.T) {
	pix := []byte{1, 2, 3, 4}
	img, err := NewImageFromRawRGBA(pix, 1, 1)
	if err != nil {
		t.Fatalf("NewImageFromRawRGBA() error = %v", err)
	}
	pix[0] = 99
	if img.Pix[0] != 1 {
		t.Fatalf("NewImageFromRawRGBA retained caller buffer")
	}
}

func TestConcurrentOperationsAreSerialized(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	img := &Image{Pix: []byte{1, 2, 3, 255}, Width: 1, Height: 1}
	var wg sync.WaitGroup
	errs := make(chan error, 16)
	for i := 0; i < cap(errs); i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := e.ResizeNearest(img, 2, 2)
			errs <- err
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("ResizeNearest() concurrent error = %v", err)
		}
	}
}

func TestWasmifyGeneratedBridge(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	req := pbAppendString(nil, 1, string([]byte{
		255, 0, 0, 255,
		0, 255, 0, 255,
		0, 0, 255, 255,
		255, 255, 255, 255,
	}))
	req = pbAppendUint32(req, 2, 2)
	req = pbAppendUint32(req, 3, 2)
	req = pbAppendUint32(req, 4, 4)
	req = pbAppendUint32(req, 5, 4)

	resp, err := e.invokeWasmify("w_0_1", req)
	if err != nil {
		t.Fatalf("callWasmifyBridge(w_0_1) error = %v", err)
	}
	got := pbReadStringField(resp, 1)
	if len(got) != 4*4*4 {
		t.Fatalf("bridge resize returned %d bytes, want %d", len(got), 4*4*4)
	}
	if got[0] != 255 || got[9] != 255 || got[34] != 255 {
		t.Fatalf("bridge resize output has unexpected pixel data: %v", []byte(got[:12]))
	}

	versionResp, err := e.invokeWasmify("w_0_2", nil)
	if err != nil {
		t.Fatalf("callWasmifyBridge(w_0_2) error = %v", err)
	}
	if got := pbReadUint32Field(versionResp, 1); got>>8 != (8<<8 | 18) {
		t.Fatalf("bridge version = %#x, want 8.18.x", got)
	}
}

func TestValidationAndClose(t *testing.T) {
	e := newTestEngine(t)

	if _, err := e.ResizeNearest(nil, 1, 1); !errors.Is(err, ErrInvalidImage) {
		t.Fatalf("ResizeNearest(nil) error = %v, want ErrInvalidImage", err)
	}
	img := &Image{Pix: make([]byte, 4), Width: 1, Height: 1}
	if _, err := e.ResizeNearest(img, 0, 1); !errors.Is(err, ErrInvalidGeometry) {
		t.Fatalf("ResizeNearest(width=0) error = %v, want ErrInvalidGeometry", err)
	}
	if _, err := NewImageFromRawRGBA([]byte{1, 2, 3}, 1, 1); !errors.Is(err, ErrInvalidImage) {
		t.Fatalf("NewImageFromRawRGBA(short) error = %v, want ErrInvalidImage", err)
	}
	if err := e.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	if _, err := e.ResizeNearest(img, 1, 1); !errors.Is(err, ErrClosed) {
		t.Fatalf("ResizeNearest(closed) error = %v, want ErrClosed", err)
	}
}

func TestPackageBuildsWithoutCGO(t *testing.T) {
	if runtime.GOOS == "js" || runtime.GOOS == "wasip1" {
		t.Skip("host-only runtime check")
	}
	if os.Getenv("VIPSWASM_CGO_BUILD_CHECK") == "1" {
		e := newTestEngine(t)
		defer e.Close()
		return
	}
	cmd := exec.Command("go", "test", ".", "-run", "^TestPackageBuildsWithoutCGO$", "-count=1")
	cmd.Env = append(os.Environ(), "CGO_ENABLED=0", "VIPSWASM_CGO_BUILD_CHECK=1")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("CGO_ENABLED=0 go test failed: %v\n%s", err, strings.TrimSpace(string(out)))
	}
}

func newTestEngine(t *testing.T) *Engine {
	t.Helper()
	e, err := New(context.Background())
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	return e
}

func assertRGBA(t *testing.T, img *image.RGBA, x, y int, want color.RGBA) {
	t.Helper()
	if got := img.RGBAAt(x, y); got != want {
		t.Fatalf("RGBAAt(%d,%d) = %+v, want %+v", x, y, got, want)
	}
}
