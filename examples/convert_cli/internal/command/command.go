package command

import (
	"bytes"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/upamune/go-vipswasm"
)

type options struct {
	format       string
	resize       geometry
	extract      area
	quality      int
	libvipsInput bool
	libvipsPNGIn bool
}

type geometry struct {
	width  int
	height int
	set    bool
}

type area struct {
	left   int
	top    int
	width  int
	height int
	set    bool
}

// Main runs the command-line program and exits the process with its status.
func Main() {
	os.Exit(Run(os.Args[1:], os.Stdout, os.Stderr))
}

// Run executes the image converter. It is separate from Main so tests can call
// the command without terminating the process.
func Run(args []string, stdout, stderr io.Writer) int {
	return run(args, os.Stdin, stdout, stderr)
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("convert_cli", flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.Usage = func() { usage(stderr) }

	var opts options
	resize := fs.String("resize", "", "resize to WIDTHxHEIGHT with libvips nearest-neighbor sampling")
	extract := fs.String("extract", "", "crop X,Y,WIDTH,HEIGHT before resizing")
	fs.StringVar(&opts.format, "format", "", "output format: png or jpeg")
	fs.IntVar(&opts.quality, "quality", 90, "JPEG quality from 1 to 100")
	fs.BoolVar(&opts.libvipsInput, "libvips-input", false, "decode input with the embedded libvips foreign loader")
	fs.BoolVar(&opts.libvipsPNGIn, "libvips-png-input", false, "decode PNG input with the embedded libvips PNG loader")

	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	rest := fs.Args()
	if len(rest) != 2 {
		usage(stderr)
		return 2
	}
	if *resize != "" {
		parsed, err := parseGeometry(*resize)
		if err != nil {
			fmt.Fprintf(stderr, "convert_cli: invalid -resize: %v\n", err)
			return 2
		}
		opts.resize = parsed
	}
	if *extract != "" {
		parsed, err := parseArea(*extract)
		if err != nil {
			fmt.Fprintf(stderr, "convert_cli: invalid -extract: %v\n", err)
			return 2
		}
		opts.extract = parsed
	}
	if _, err := outputFormat(rest[1], opts.format); err != nil {
		fmt.Fprintf(stderr, "convert_cli: %v\n", err)
		return 2
	}
	if opts.quality < 1 || opts.quality > 100 {
		fmt.Fprintln(stderr, "convert_cli: -quality must be between 1 and 100")
		return 2
	}

	if err := convert(context.Background(), rest[0], rest[1], opts, stdin, stdout); err != nil {
		fmt.Fprintf(stderr, "convert_cli: %v\n", err)
		return 1
	}
	return 0
}

func usage(w io.Writer) {
	fmt.Fprintln(w, "usage: convert_cli [flags] <input> <output>")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "flags:")
	fmt.Fprintln(w, "  -format png|jpeg          output format; required when output is -")
	fmt.Fprintln(w, "  -resize WIDTHxHEIGHT      resize with libvips nearest-neighbor sampling")
	fmt.Fprintln(w, "  -extract X,Y,WIDTH,HEIGHT crop before resizing")
	fmt.Fprintln(w, "  -quality 1..100           JPEG quality, default 90")
	fmt.Fprintln(w, "  -libvips-input            decode input with the embedded libvips foreign loader")
	fmt.Fprintln(w, "  -libvips-png-input        decode PNG input with the embedded libvips loader")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "examples:")
	fmt.Fprintln(w, "  convert_cli input.png output.jpg")
	fmt.Fprintln(w, "  convert_cli -resize 320x240 input.png thumb.png")
	fmt.Fprintln(w, "  convert_cli -extract 10,10,200,120 -format jpeg input.png - > out.jpg")
}

func convert(ctx context.Context, inputPath, outputPath string, opts options, stdin io.Reader, stdout io.Writer) error {
	input, err := readInput(inputPath, stdin)
	if err != nil {
		return err
	}

	engine, err := vipswasm.New(ctx)
	if err != nil {
		return err
	}
	defer engine.Close()

	img, err := decodeInput(engine, inputPath, input, opts)
	if err != nil {
		return err
	}
	if opts.extract.set {
		img, err = engine.ExtractArea(img, opts.extract.left, opts.extract.top, opts.extract.width, opts.extract.height)
		if err != nil {
			return err
		}
	}
	if opts.resize.set {
		img, err = engine.ResizeNearest(img, opts.resize.width, opts.resize.height)
		if err != nil {
			return err
		}
	}

	format, err := outputFormat(outputPath, opts.format)
	if err != nil {
		return err
	}
	var encoded bytes.Buffer
	if err := encodeOutput(img, &encoded, format, opts.quality); err != nil {
		return err
	}
	return writeOutput(outputPath, encoded.Bytes(), stdout)
}

func readInput(path string, stdin io.Reader) ([]byte, error) {
	if path == "-" {
		return io.ReadAll(stdin)
	}
	return os.ReadFile(path)
}

func decodeInput(engine *vipswasm.Engine, path string, input []byte, opts options) (*vipswasm.Image, error) {
	if opts.libvipsInput || shouldUseLibvipsInput(path) {
		return engine.DecodeImage(input)
	}
	if opts.libvipsPNGIn {
		return engine.DecodePNG(input)
	}
	img, _, err := vipswasm.Decode(bytes.NewReader(input))
	return img, err
}

func shouldUseLibvipsInput(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".avif", ".heic", ".heif":
		return true
	default:
		return false
	}
}

func writeOutput(path string, data []byte, stdout io.Writer) error {
	if path == "-" {
		_, err := stdout.Write(data)
		return err
	}
	return writeFileAtomic(path, data, 0o644)
}

func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	base := filepath.Base(path)
	file, err := os.CreateTemp(dir, "."+base+".tmp-*")
	if err != nil {
		return err
	}
	tmp := file.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tmp)
		}
	}()
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Chmod(perm); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		return err
	}
	cleanup = false
	return nil
}

func outputFormat(path, explicit string) (string, error) {
	format := strings.ToLower(strings.TrimPrefix(explicit, "."))
	if format == "" {
		switch strings.ToLower(filepath.Ext(path)) {
		case ".jpg", ".jpeg":
			format = "jpeg"
		case ".png":
			format = "png"
		}
	}
	if format == "" && path == "-" {
		return "", fmt.Errorf("-format is required when output is -")
	}
	switch format {
	case "jpg":
		return "jpeg", nil
	case "jpeg", "png":
		return format, nil
	default:
		return "", fmt.Errorf("unsupported output format %q", format)
	}
}

func encodeOutput(img *vipswasm.Image, out io.Writer, format string, quality int) error {
	switch format {
	case "png":
		return img.EncodePNG(out)
	case "jpeg":
		return img.EncodeJPEG(out, &vipswasm.JPEGOptions{Quality: quality})
	default:
		return fmt.Errorf("unsupported output format %q", format)
	}
}

func parseGeometry(value string) (geometry, error) {
	parts := strings.Split(value, "x")
	if len(parts) != 2 {
		return geometry{}, fmt.Errorf("expected WIDTHxHEIGHT")
	}
	width, err := parsePositive(parts[0], "width")
	if err != nil {
		return geometry{}, err
	}
	height, err := parsePositive(parts[1], "height")
	if err != nil {
		return geometry{}, err
	}
	return geometry{width: width, height: height, set: true}, nil
}

func parseArea(value string) (area, error) {
	parts := strings.Split(value, ",")
	if len(parts) != 4 {
		return area{}, fmt.Errorf("expected X,Y,WIDTH,HEIGHT")
	}
	left, err := parseNonNegative(parts[0], "x")
	if err != nil {
		return area{}, err
	}
	top, err := parseNonNegative(parts[1], "y")
	if err != nil {
		return area{}, err
	}
	width, err := parsePositive(parts[2], "width")
	if err != nil {
		return area{}, err
	}
	height, err := parsePositive(parts[3], "height")
	if err != nil {
		return area{}, err
	}
	return area{left: left, top: top, width: width, height: height, set: true}, nil
}

func parsePositive(value, name string) (int, error) {
	n, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || n <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer", name)
	}
	return n, nil
}

func parseNonNegative(value, name string) (int, error) {
	n, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || n < 0 {
		return 0, fmt.Errorf("%s must be a non-negative integer", name)
	}
	return n, nil
}
