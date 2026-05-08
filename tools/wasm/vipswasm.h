#pragma once

#include <stdint.h>
#include <string>

namespace vipswasm {

uint32_t version();
std::string resize_nearest(const std::string& src, uint32_t src_width,
                           uint32_t src_height, uint32_t dst_width,
                           uint32_t dst_height);
std::string extract_area(const std::string& src, uint32_t src_width,
                         uint32_t src_height, uint32_t left, uint32_t top,
                         uint32_t width, uint32_t height);

}

#ifdef __cplusplus
extern "C" {
#endif

void* vipswasm_alloc(uint32_t size);
void vipswasm_free(void* ptr);
uint32_t vipswasm_version(void);
int32_t vipswasm_resize_nearest(const uint8_t* src, uint32_t src_width,
                                uint32_t src_height, uint8_t* dst,
                                uint32_t dst_width, uint32_t dst_height);
int32_t vipswasm_extract_area(const uint8_t* src, uint32_t src_width,
                              uint32_t src_height, uint8_t* dst,
                              uint32_t left, uint32_t top,
                              uint32_t width, uint32_t height);
int32_t vipswasm_load_rgba(const uint8_t* src, uint32_t src_len,
                           uint8_t** dst, uint32_t* dst_len,
                           uint32_t* width, uint32_t* height);
int32_t vipswasm_pngload_rgba(const uint8_t* src, uint32_t src_len,
                              uint8_t** dst, uint32_t* dst_len,
                              uint32_t* width, uint32_t* height);
int32_t vipswasm_save_rgba(const uint8_t* src, uint32_t src_width,
                           uint32_t src_height, const char* suffix,
                           uint32_t suffix_len, uint8_t** dst,
                           uint32_t* dst_len);

#ifdef __cplusplus
}
#endif
