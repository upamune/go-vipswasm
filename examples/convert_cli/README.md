# convert_cli scratch demo

`convert_cli` is a small command-line example for `go-vipswasm`. It builds to a single statically linked, CGO-free Go binary that embeds the libvips-backed WASM core.

The Dockerfile is intentionally multi-stage:

1. `golang:1.24` builds `convert_cli` with `CGO_ENABLED=0`.
2. `alpine` downloads a sample HEIC file during the image build.
3. `scratch` receives only the binary and the sample file.

The final runtime image has no shell, package manager, libvips shared library, ImageMagick, or codec shared libraries.

## Build

```sh
docker build -f examples/convert_cli/Dockerfile -t go-vipswasm-convert-cli:scratch .
```

## Run the embedded HEIC sample

The build stage downloads this sample into the final scratch image:

```text
/tmp/shelf-christmas-decoration.heic
```

Convert it to files on the host:

```sh
mkdir -p /tmp/go-vipswasm-out

docker run --rm \
  --mount type=bind,src=/tmp/go-vipswasm-out,dst=/out \
  go-vipswasm-convert-cli:scratch \
  /tmp/shelf-christmas-decoration.heic /out/shelf.png

docker run --rm \
  --mount type=bind,src=/tmp/go-vipswasm-out,dst=/out \
  go-vipswasm-convert-cli:scratch \
  /tmp/shelf-christmas-decoration.heic /out/shelf.webp

docker run --rm \
  --mount type=bind,src=/tmp/go-vipswasm-out,dst=/out \
  go-vipswasm-convert-cli:scratch \
  -resize 320x240 /tmp/shelf-christmas-decoration.heic /out/thumb.webp
```

## Use your own input

```sh
docker run --rm \
  --mount type=bind,src="$PWD",dst=/work \
  go-vipswasm-convert-cli:scratch \
  /work/input.heic /work/output.png
```

Use `-format` when writing to stdout because the output path cannot provide an
extension:

```sh
docker run --rm -i go-vipswasm-convert-cli:scratch \
  -format webp - - < input.png > output.webp
```

## Runtime notes

- All decoding uses the embedded libvips WASM runtime.
- PNG, WebP, TIFF, GIF, JPEG 2000, and raw RGBA outputs use `Engine.EncodeImage`. JPEG output is intentionally unsupported until the embedded core exposes a working libvips JPEG saver.
- `-resize` uses the libvips-backed WASM operation.
- The final image is `scratch`; `/bin/sh` intentionally does not exist.
