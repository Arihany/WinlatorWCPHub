#pragma once

#if defined(SAREK_ARM64EC) || defined(__arm64ec__) || defined(_M_ARM64EC)

#include <cstdint>

#if !defined(__aarch64__) && !defined(__arm64ec__) && !defined(_M_ARM64EC)
  #error "SAREK_ARM64EC enabled but target is not AArch64/ARM64EC (NEON required, no fallback)."
#endif

#include <arm_neon.h>

typedef float32x4_t __m128;
typedef uint8x16_t  __m128i;

static inline void _mm_pause(void) {
  __asm__ __volatile__("yield" ::: "memory");
}

// --- Load / Store ---
static inline __m128 _mm_loadu_ps(const float* p) {
  return vld1q_f32(p);
}

static inline void _mm_storeu_ps(float* p, __m128 a) {
  vst1q_f32(p, a);
}

static inline __m128i _mm_load_si128(const __m128i* p) {
  return vld1q_u8((const uint8_t*)p);
}

static inline __m128i _mm_loadu_si128(const __m128i* p) {
  return vld1q_u8((const uint8_t*)p);
}

static inline void _mm_store_si128(__m128i* p, __m128i a) {
  vst1q_u8((uint8_t*)p, a);
}

static inline void _mm_storeu_si128(__m128i* p, __m128i a) {
  vst1q_u8((uint8_t*)p, a);
}

// --- Float Logic ---
static inline __m128 _mm_cmpeq_ps(__m128 a, __m128 b) {
  return vreinterpretq_f32_u32(vceqq_f32(a, b));
}

static inline __m128 _mm_and_ps(__m128 a, __m128 b) {
  return vreinterpretq_f32_u32(
    vandq_u32(vreinterpretq_u32_f32(a), vreinterpretq_u32_f32(b))
  );
}

// --- Integer Logic ---
static inline __m128i _mm_setzero_si128() {
  return vdupq_n_u8(0);
}

static inline __m128i _mm_set1_epi8(int x) {
  return vdupq_n_u8((uint8_t)x);
}

static inline __m128i _mm_cmpeq_epi8(__m128i a, __m128i b) {
  return vceqq_u8(a, b);
}

static inline __m128i _mm_and_si128(__m128i a, __m128i b) {
  return vandq_u8(a, b);
}

static inline __m128i _mm_or_si128(__m128i a, __m128i b) {
  return vorrq_u8(a, b);
}

static inline __m128i _mm_xor_si128(__m128i a, __m128i b) {
  return veorq_u8(a, b);
}

// no store-to-stack loop
static inline int _mm_movemask_epi8(__m128i a) {
  uint8x16_t bits8 = vshrq_n_u8(a, 7);

  uint16x8_t lo = vmovl_u8(vget_low_u8(bits8));
  uint16x8_t hi = vmovl_u8(vget_high_u8(bits8));

  const uint16_t wlo_arr[8] = { 1, 2, 4, 8, 16, 32, 64, 128 };
  const uint16_t whi_arr[8] = { 256, 512, 1024, 2048, 4096, 8192, 16384, 32768 };
  uint16x8_t wlo = vld1q_u16(wlo_arr);
  uint16x8_t whi = vld1q_u16(whi_arr);

  lo = vmulq_u16(lo, wlo);
  hi = vmulq_u16(hi, whi);

  uint32x4_t s0 = vpaddlq_u16(lo);
  uint32x4_t s1 = vpaddlq_u16(hi);
  uint64x2_t t0 = vpaddlq_u32(s0);
  uint64x2_t t1 = vpaddlq_u32(s1);

  uint64_t m =
    vgetq_lane_u64(t0, 0) + vgetq_lane_u64(t0, 1) +
    vgetq_lane_u64(t1, 0) + vgetq_lane_u64(t1, 1);

  return (int)m;
}

#if defined(__SSE__) || defined(__SSE2__) || defined(__SSE3__) || \
    defined(__SSSE3__) || defined(__SSE4_1__) || defined(__SSE4_2__) || \
    defined(__AVX__)  || defined(__AVX2__)
  #error "x86 SIMD macros must not be defined on ARM64EC build"
#endif

#endif // SAREK_ARM64EC / __arm64ec__ / _M_ARM64EC
