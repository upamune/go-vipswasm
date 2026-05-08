#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>

#ifdef VIPSWASM_USE_LIBVIPS
#include <vips/vips.h>
extern "C" void glib_init(void);
extern "C" int vips__png_read_source(VipsSource* source, VipsImage* out,
                                     VipsFailOn fail_on, gboolean unlimited);
#endif

#include "vipswasm.h"

#define WASM_EXPORT(name) __attribute__((export_name(#name)))

namespace vipswasm {

namespace {

#ifdef VIPSWASM_USE_LIBVIPS
bool ensure_vips() {
  glib_init();
  return vips_init("go-vipswasm") == 0;
}

uint8_t* copy_to_malloc(const void* src, size_t len) {
  if (src == nullptr || len == 0 || len > UINT32_MAX) {
    return nullptr;
  }
  uint8_t* out = static_cast<uint8_t*>(std::malloc(len));
  if (out == nullptr) {
    return nullptr;
  }
  std::memcpy(out, src, len);
  return out;
}

int32_t image_to_rgba(VipsImage* loaded, uint8_t** dst, uint32_t* dst_len,
                      uint32_t* width, uint32_t* height) {
  if (loaded == nullptr || dst == nullptr || dst_len == nullptr ||
      width == nullptr || height == nullptr) {
    return -1;
  }

  VipsImage* work = loaded;
  if (work->BandFmt != VIPS_FORMAT_UCHAR) {
    VipsImage* casted = nullptr;
    if (vips_cast(work, &casted, VIPS_FORMAT_UCHAR, nullptr) != 0 ||
        casted == nullptr) {
      g_object_unref(work);
      return -1;
    }
    g_object_unref(work);
    work = casted;
  }

  if (work->Bands < 3) {
    VipsImage* rgb = nullptr;
    if (vips_colourspace(work, &rgb, VIPS_INTERPRETATION_sRGB, nullptr) != 0 ||
        rgb == nullptr) {
      g_object_unref(work);
      return -1;
    }
    g_object_unref(work);
    work = rgb;
  }

  if (work->Bands == 3) {
    VipsImage* with_alpha = nullptr;
    double alpha = 255.0;
    if (vips_bandjoin_const(work, &with_alpha, &alpha, 1, nullptr) != 0 ||
        with_alpha == nullptr) {
      g_object_unref(work);
      return -1;
    }
    g_object_unref(work);
    work = with_alpha;
  } else if (work->Bands > 4) {
    VipsImage* first_four = nullptr;
    if (vips_extract_band(work, &first_four, 0, "n", 4, nullptr) != 0 ||
        first_four == nullptr) {
      g_object_unref(work);
      return -1;
    }
    g_object_unref(work);
    work = first_four;
  }

  if (work->Bands != 4) {
    g_object_unref(work);
    return -1;
  }

  size_t len = 0;
  void* pixels = vips_image_write_to_memory(work, &len);
  const uint32_t image_width = static_cast<uint32_t>(work->Xsize);
  const uint32_t image_height = static_cast<uint32_t>(work->Ysize);
  g_object_unref(work);
  uint8_t* copied = vipswasm::copy_to_malloc(pixels, len);
  if (pixels != nullptr) {
    g_free(pixels);
  }
  if (copied == nullptr || len > UINT32_MAX) {
    if (copied != nullptr) {
      std::free(copied);
    }
    return -1;
  }
  *dst = copied;
  *dst_len = static_cast<uint32_t>(len);
  *width = image_width;
  *height = image_height;
  return 0;
}

#endif

}  // namespace

uint32_t version() {
  return vipswasm_version();
}

std::string resize_nearest(const std::string& src, uint32_t src_width,
                           uint32_t src_height, uint32_t dst_width,
                           uint32_t dst_height) {
  if (src.size() != static_cast<size_t>(src_width) * src_height * 4) {
    return {};
  }
  std::string dst(static_cast<size_t>(dst_width) * dst_height * 4, '\0');
  if (vipswasm_resize_nearest(reinterpret_cast<const uint8_t*>(src.data()), src_width, src_height,
                              reinterpret_cast<uint8_t*>(&dst[0]),
                              dst_width, dst_height) != 0) {
    return {};
  }
  return dst;
}

std::string extract_area(const std::string& src, uint32_t src_width,
                         uint32_t src_height, uint32_t left, uint32_t top,
                         uint32_t width, uint32_t height) {
  if (src.size() != static_cast<size_t>(src_width) * src_height * 4) {
    return {};
  }
  std::string dst(static_cast<size_t>(width) * height * 4, '\0');
  if (vipswasm_extract_area(reinterpret_cast<const uint8_t*>(src.data()), src_width, src_height,
                            reinterpret_cast<uint8_t*>(&dst[0]),
                            left, top, width, height) != 0) {
    return {};
  }
  return dst;
}

WASM_EXPORT(vipswasm_pngload_rgba)
int32_t vipswasm_pngload_rgba(const uint8_t* src, uint32_t src_len,
                              uint8_t** dst, uint32_t* dst_len,
                              uint32_t* width, uint32_t* height) {
  if (src == nullptr || src_len == 0 || dst == nullptr || dst_len == nullptr ||
      width == nullptr || height == nullptr) {
    return -1;
  }
  *dst = nullptr;
  *dst_len = 0;
  *width = 0;
  *height = 0;

#ifdef VIPSWASM_USE_LIBVIPS
  if (!vipswasm::ensure_vips()) {
    return -1;
  }
  VipsSource* source = vips_source_new_from_memory(src, src_len);
  if (source == nullptr) {
    return -1;
  }
  VipsImage* loaded = vips_image_new();
  if (loaded == nullptr) {
    g_object_unref(source);
    return -1;
  }
  if (vips__png_read_source(source, loaded, VIPS_FAIL_ON_NONE, FALSE) != 0) {
    g_object_unref(source);
    g_object_unref(loaded);
    return -1;
  }
  g_object_unref(source);
  return vipswasm::image_to_rgba(loaded, dst, dst_len, width, height);
#else
  return -1;
#endif
}

WASM_EXPORT(vipswasm_load_rgba)
int32_t vipswasm_load_rgba(const uint8_t* src, uint32_t src_len,
                           uint8_t** dst, uint32_t* dst_len,
                           uint32_t* width, uint32_t* height) {
  if (src == nullptr || src_len == 0 || dst == nullptr || dst_len == nullptr ||
      width == nullptr || height == nullptr) {
    return -1;
  }
  *dst = nullptr;
  *dst_len = 0;
  *width = 0;
  *height = 0;

#ifdef VIPSWASM_USE_LIBVIPS
  if (!vipswasm::ensure_vips()) {
    return -1;
  }
  VipsImage* loaded = vips_image_new_from_buffer(src, src_len, "", nullptr);
  if (loaded == nullptr) {
    return -1;
  }
  return vipswasm::image_to_rgba(loaded, dst, dst_len, width, height);
#else
  return -1;
#endif
}

WASM_EXPORT(vipswasm_save_rgba)
int32_t vipswasm_save_rgba(const uint8_t* src, uint32_t src_width,
                           uint32_t src_height, const char* suffix,
                           uint32_t suffix_len, uint8_t** dst,
                           uint32_t* dst_len) {
  if (src == nullptr || src_width == 0 || src_height == 0 ||
      suffix == nullptr || suffix_len == 0 || dst == nullptr ||
      dst_len == nullptr) {
    return -1;
  }
  *dst = nullptr;
  *dst_len = 0;

#ifdef VIPSWASM_USE_LIBVIPS
  if (!vipswasm::ensure_vips()) {
    return -1;
  }
  const uint64_t pixel_len = static_cast<uint64_t>(src_width) * src_height * 4;
  if (pixel_len > SIZE_MAX) {
    return -1;
  }
  VipsImage* in = vips_image_new_from_memory_copy(
      src, static_cast<size_t>(pixel_len), src_width, src_height, 4,
      VIPS_FORMAT_UCHAR);
  if (in == nullptr) {
    return -1;
  }
  VipsImage* srgb = nullptr;
  if (vips_copy(in, &srgb, "interpretation", VIPS_INTERPRETATION_sRGB,
                nullptr) != 0 ||
      srgb == nullptr) {
    g_object_unref(in);
    return -1;
  }
  g_object_unref(in);

  const std::string save_suffix(suffix, suffix_len);
  void* encoded = nullptr;
  size_t encoded_len = 0;
  const int ret = vips_image_write_to_buffer(
      srgb, save_suffix.c_str(), &encoded, &encoded_len, nullptr);
  g_object_unref(srgb);
  if (ret != 0 || encoded == nullptr || encoded_len == 0 ||
      encoded_len > UINT32_MAX) {
    if (encoded != nullptr) {
      g_free(encoded);
    }
    return -1;
  }

  *dst = static_cast<uint8_t*>(encoded);
  *dst_len = static_cast<uint32_t>(encoded_len);
  return 0;
#else
  return -1;
#endif
}

}

extern "C" {

WASM_EXPORT(vipswasm_alloc)
void* vipswasm_alloc(uint32_t size) {
  return std::malloc(size);
}

WASM_EXPORT(vipswasm_free)
void vipswasm_free(void* ptr) {
  std::free(ptr);
}

WASM_EXPORT(vipswasm_version)
uint32_t vipswasm_version() {
#ifdef VIPSWASM_USE_LIBVIPS
  glib_init();
  return (static_cast<uint32_t>(vips_version(0)) << 16) |
         (static_cast<uint32_t>(vips_version(1)) << 8) |
         static_cast<uint32_t>(vips_version(2));
#else
  return (8u << 16) | (18u << 8) | 0u;
#endif
}

WASM_EXPORT(vipswasm_resize_nearest)
int32_t vipswasm_resize_nearest(const uint8_t* src, uint32_t src_width,
                                uint32_t src_height, uint8_t* dst,
                                uint32_t dst_width, uint32_t dst_height) {
  if (src == nullptr || dst == nullptr || src_width == 0 || src_height == 0 ||
      dst_width == 0 || dst_height == 0) {
    return -1;
  }

#ifdef VIPSWASM_USE_LIBVIPS
  if (!vipswasm::ensure_vips()) {
    return -1;
  }
  VipsImage* in = vips_image_new_from_memory_copy(
      src, static_cast<size_t>(src_width) * src_height * 4, src_width,
      src_height, 4, VIPS_FORMAT_UCHAR);
  if (in == nullptr) {
    return -1;
  }
  VipsImage* out = nullptr;
  const double hscale = static_cast<double>(dst_width) / src_width;
  const double vscale = static_cast<double>(dst_height) / src_height;
  const int ret =
      vips_resize(in, &out, hscale, "vscale", vscale, "kernel",
                  VIPS_KERNEL_NEAREST, nullptr);
  g_object_unref(in);
  if (ret != 0 || out == nullptr) {
    return -1;
  }
  size_t len = 0;
  void* data = vips_image_write_to_memory(out, &len);
  g_object_unref(out);
  const size_t want = static_cast<size_t>(dst_width) * dst_height * 4;
  if (data == nullptr || len != want) {
    if (data != nullptr) {
      g_free(data);
    }
    return -1;
  }
  std::memcpy(dst, data, want);
  g_free(data);
  return 0;
#else
  for (uint32_t y = 0; y < dst_height; ++y) {
    const uint32_t sy = static_cast<uint64_t>(y) * src_height / dst_height;
    for (uint32_t x = 0; x < dst_width; ++x) {
      const uint32_t sx = static_cast<uint64_t>(x) * src_width / dst_width;
      const uint8_t* in = src + ((static_cast<uint64_t>(sy) * src_width + sx) * 4);
      uint8_t* out = dst + ((static_cast<uint64_t>(y) * dst_width + x) * 4);
      std::memcpy(out, in, 4);
    }
  }
  return 0;
#endif
}

WASM_EXPORT(vipswasm_extract_area)
int32_t vipswasm_extract_area(const uint8_t* src, uint32_t src_width,
                              uint32_t src_height, uint8_t* dst,
                              uint32_t left, uint32_t top,
                              uint32_t width, uint32_t height) {
  if (src == nullptr || dst == nullptr || src_width == 0 || src_height == 0 ||
      width == 0 || height == 0 || left > src_width || top > src_height ||
      width > src_width - left || height > src_height - top) {
    return -1;
  }

#ifdef VIPSWASM_USE_LIBVIPS
  if (!vipswasm::ensure_vips()) {
    return -1;
  }
  VipsImage* in = vips_image_new_from_memory_copy(
      src, static_cast<size_t>(src_width) * src_height * 4, src_width,
      src_height, 4, VIPS_FORMAT_UCHAR);
  if (in == nullptr) {
    return -1;
  }
  VipsImage* out = nullptr;
  const int ret =
      vips_extract_area(in, &out, left, top, width, height, nullptr);
  g_object_unref(in);
  if (ret != 0 || out == nullptr) {
    return -1;
  }
  size_t len = 0;
  void* data = vips_image_write_to_memory(out, &len);
  g_object_unref(out);
  const size_t want = static_cast<size_t>(width) * height * 4;
  if (data == nullptr || len != want) {
    if (data != nullptr) {
      g_free(data);
    }
    return -1;
  }
  std::memcpy(dst, data, want);
  g_free(data);
  return 0;
#else
  for (uint32_t y = 0; y < height; ++y) {
    const uint8_t* in = src + ((static_cast<uint64_t>(top + y) * src_width + left) * 4);
    uint8_t* out = dst + (static_cast<uint64_t>(y) * width * 4);
    std::memcpy(out, in, static_cast<size_t>(width) * 4);
  }
  return 0;
#endif
}

}
