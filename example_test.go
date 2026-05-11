package vipswasm_test

import (
	"context"
	"image"
	"image/color"
	"log"

	"github.com/upamune/go-vipswasm"
)

func ExampleEngine_ResizeNearest() {
	engine, err := vipswasm.New(context.Background())
	if err != nil {
		log.Fatal(err)
	}
	defer engine.Close()

	src := image.NewRGBA(image.Rect(0, 0, 1, 1))
	src.SetRGBA(0, 0, color.RGBA{R: 255, A: 255})
	img, err := vipswasm.NewImageFromRGBA(src)
	if err != nil {
		log.Fatal(err)
	}

	thumb, err := engine.ResizeNearest(img, 2, 2)
	if err != nil {
		log.Fatal(err)
	}
	out, err := engine.EncodeImage(thumb, "png", nil)
	if err != nil {
		log.Fatal(err)
	}
	log.Println(thumb.Width, thumb.Height, len(out) > 0)
}
