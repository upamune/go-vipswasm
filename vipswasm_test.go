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

func TestDecodeAndEncodePNG(t *testing.T) {
	e := newTestEngine(t)
	defer e.Close()

	src := image.NewRGBA(image.Rect(0, 0, 2, 1))
	src.SetRGBA(0, 0, color.RGBA{R: 1, G: 2, B: 3, A: 255})
	src.SetRGBA(1, 0, color.RGBA{R: 4, G: 5, B: 6, A: 255})

	img, err := NewImageFromRGBA(src)
	if err != nil {
		t.Fatalf("NewImageFromRGBA() error = %v", err)
	}
	var encoded bytes.Buffer
	if err := img.EncodePNG(&encoded); err != nil {
		t.Fatalf("Image.EncodePNG() error = %v", err)
	}
	got, err := e.DecodePNG(encoded.Bytes())
	if err != nil {
		t.Fatalf("Engine.DecodePNG() error = %v", err)
	}
	out, err := got.ToRGBA()
	if err != nil {
		t.Fatalf("ToRGBA() error = %v", err)
	}
	assertRGBA(t, out, 0, 0, color.RGBA{R: 1, G: 2, B: 3, A: 255})
	assertRGBA(t, out, 1, 0, color.RGBA{R: 4, G: 5, B: 6, A: 255})

	generic, err := e.DecodeImage(encoded.Bytes())
	if err != nil {
		t.Fatalf("Engine.DecodeImage() error = %v", err)
	}
	if generic.Width != 2 || generic.Height != 1 {
		t.Fatalf("Engine.DecodeImage() size = %dx%d, want 2x1", generic.Width, generic.Height)
	}

	encodedPNG, err := e.EncodeImage(img, "png", nil)
	if err != nil {
		t.Fatalf("Engine.EncodeImage(png) error = %v", err)
	}
	if len(encodedPNG) < 8 || string(encodedPNG[:8]) != "\x89PNG\r\n\x1a\n" {
		t.Fatalf("Engine.EncodeImage(png) did not return PNG")
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
	var buf bytes.Buffer
	if err := img.EncodeJPEG(&buf, &JPEGOptions{Quality: 101}); !errors.Is(err, ErrInvalidGeometry) {
		t.Fatalf("EncodeJPEG(quality=101) error = %v, want ErrInvalidGeometry", err)
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
