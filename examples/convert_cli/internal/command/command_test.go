package command

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunConvertsAndResizesPNGToJPEG(t *testing.T) {
	dir := t.TempDir()
	input := filepath.Join(dir, "input.png")
	output := filepath.Join(dir, "output.jpg")

	if err := os.WriteFile(input, testPNG(t), 0o644); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := Run([]string{"-resize", "4x4", input, output}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("Run() = %d, stderr = %s", code, stderr.String())
	}
	info, err := os.Stat(output)
	if err != nil {
		t.Fatal(err)
	}
	if info.Size() == 0 {
		t.Fatal("output is empty")
	}
	file, err := os.Open(output)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	got, err := jpeg.Decode(file)
	if err != nil {
		t.Fatal(err)
	}
	if got.Bounds().Dx() != 4 || got.Bounds().Dy() != 4 {
		t.Fatalf("output size = %dx%d, want 4x4", got.Bounds().Dx(), got.Bounds().Dy())
	}
}

func TestRunWritesPNGToStdout(t *testing.T) {
	dir := t.TempDir()
	input := filepath.Join(dir, "input.png")
	if err := os.WriteFile(input, testPNG(t), 0o644); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := Run([]string{"-extract", "1,0,1,2", "-format", "png", input, "-"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("Run() = %d, stderr = %s", code, stderr.String())
	}
	got, err := png.Decode(bytes.NewReader(stdout.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	if got.Bounds().Dx() != 1 || got.Bounds().Dy() != 2 {
		t.Fatalf("stdout image size = %dx%d, want 1x2", got.Bounds().Dx(), got.Bounds().Dy())
	}
}

func TestRunDecodesStdinWithLibvipsPNGLoader(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"-libvips-png-input", "-format", "png", "-", "-"}, bytes.NewReader(testPNG(t)), &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run() = %d, stderr = %s", code, stderr.String())
	}
	got, err := png.Decode(bytes.NewReader(stdout.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	if got.Bounds().Dx() != 2 || got.Bounds().Dy() != 2 {
		t.Fatalf("stdout image size = %dx%d, want 2x2", got.Bounds().Dx(), got.Bounds().Dy())
	}
}

func TestRunRejectsUnknownFormat(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := Run([]string{"-format", "gif", "input.png", "-"}, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("Run() = %d, want 2", code)
	}
}

func TestRunRequiresFormatForStdout(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := Run([]string{"input.png", "-"}, &stdout, &stderr)
	if code != 2 {
		t.Fatalf("Run() = %d, want 2", code)
	}
	if !strings.Contains(stderr.String(), "-format is required") {
		t.Fatalf("stderr = %q, want format requirement", stderr.String())
	}
}

func TestRunHelpExitsSuccessfully(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := Run([]string{"-h"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("Run() = %d, want 0", code)
	}
	if !strings.Contains(stderr.String(), "usage: convert_cli") {
		t.Fatalf("stderr = %q, want usage", stderr.String())
	}
}

func TestRunDoesNotReplaceOutputOnConversionError(t *testing.T) {
	dir := t.TempDir()
	input := filepath.Join(dir, "input.png")
	output := filepath.Join(dir, "output.png")
	original := []byte("keep me")
	if err := os.WriteFile(input, testPNG(t), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(output, original, 0o644); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := Run([]string{"-extract", "1,1,5,5", input, output}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("Run() = %d, want 1; stderr = %s", code, stderr.String())
	}
	got, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, original) {
		t.Fatalf("output changed after failed conversion: %q", got)
	}
}

func TestParseValidation(t *testing.T) {
	if _, err := parseGeometry("10"); err == nil {
		t.Fatal("parseGeometry accepted missing height")
	}
	if _, err := parseGeometry("0x10"); err == nil {
		t.Fatal("parseGeometry accepted zero width")
	}
	if _, err := parseArea("-1,0,10,10"); err == nil {
		t.Fatal("parseArea accepted negative x")
	}
	if _, err := parseArea("0,0,10,0"); err == nil {
		t.Fatal("parseArea accepted zero height")
	}
}

func testPNG(t *testing.T) []byte {
	t.Helper()
	src := image.NewRGBA(image.Rect(0, 0, 2, 2))
	src.SetRGBA(0, 0, color.RGBA{R: 255, A: 255})
	src.SetRGBA(1, 0, color.RGBA{G: 255, A: 255})
	src.SetRGBA(0, 1, color.RGBA{B: 255, A: 255})
	src.SetRGBA(1, 1, color.RGBA{R: 255, G: 255, A: 255})
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, src); err != nil {
		t.Fatal(err)
	}
	return encoded.Bytes()
}
