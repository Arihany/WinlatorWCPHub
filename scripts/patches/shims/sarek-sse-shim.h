#pragma once

#if defined(SAREK_ARM64EC) || defined(__arm64ec__) || defined(_M_ARM64EC)

#include <cstdint>
#include <cstring>

// =========================================================
// Path A: Hardware NEON Acceleration (Preferred)
// =========================================================
#if defined(__aarch64__) || defined(__arm64ec__) || defined(_M_ARM64EC)

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

// Note: Slow but correct implementation
static inline int _mm_movemask_epi8(__m128i a) {
    alignas(16) uint8_t tmp[16];
    vst1q_u8(tmp, a);
    int m = 0;
    for (int i = 0; i < 16; i++) {
        m |= ((tmp[i] & 0x80) ? 1 : 0) << i;
    }
    return m;
}

// =========================================================
// Path B: Generic Scalar Fallback (Safety Net)
// =========================================================
#else

struct alignas(16) __m128  { float   v[4];  };
struct alignas(16) __m128i { uint8_t v[16]; };

static inline void _mm_pause(void) {
    __asm__ __volatile__("" ::: "memory");
}

static inline __m128 _mm_loadu_ps(const float* p) {
    __m128 r;
    std::memcpy(r.v, p, 16);
    return r;
}

static inline void _mm_storeu_ps(float* p, __m128 a) {
    std::memcpy(p, a.v, 16);
}

static inline __m128 _mm_cmpeq_ps(__m128 a, __m128 b) {
    __m128 r;
    for (int i = 0; i < 4; i++) {
        uint32_t m = (a.v[i] == b.v[i]) ? 0xFFFFFFFFu : 0u;
        std::memcpy(&r.v[i], &m, 4);
    }
    return r;
}

static inline __m128 _mm_and_ps(__m128 a, __m128 b) {
    __m128 r;
    for (int i = 0; i < 4; i++) {
        uint32_t ai, bi, ci;
        std::memcpy(&ai, &a.v[i], 4);
        std::memcpy(&bi, &b.v[i], 4);
        ci = ai & bi;
        std::memcpy(&r.v[i], &ci, 4);
    }
    return r;
}

static inline __m128i _mm_setzero_si128() {
    __m128i r;
    std::memset(r.v, 0, 16);
    return r;
}

static inline __m128i _mm_set1_epi8(int x) {
    __m128i r;
    uint8_t v = (uint8_t)x;
    for (int i = 0; i < 16; i++) r.v[i] = v;
    return r;
}

static inline __m128i _mm_load_si128(const __m128i* p) {
    __m128i r;
    std::memcpy(&r, p, 16);
    return r;
}

static inline __m128i _mm_loadu_si128(const __m128i* p) {
    return _mm_load_si128(p);
}

static inline void _mm_store_si128(__m128i* p, __m128i a) {
    std::memcpy(p, &a, 16);
}

static inline void _mm_storeu_si128(__m128i* p, __m128i a) {
    _mm_store_si128(p, a);
}

static inline __m128i _mm_cmpeq_epi8(__m128i a, __m128i b) {
    __m128i r;
    for (int i = 0; i < 16; i++)
        r.v[i] = (a.v[i] == b.v[i]) ? 0xFF : 0x00;
    return r;
}

static inline __m128i _mm_and_si128(__m128i a, __m128i b) {
    __m128i r;
    for (int i = 0; i < 16; i++) r.v[i] = a.v[i] & b.v[i];
    return r;
}

static inline __m128i _mm_or_si128(__m128i a, __m128i b) {
    __m128i r;
    for (int i = 0; i < 16; i++) r.v[i] = a.v[i] | b.v[i];
    return r;
}

static inline __m128i _mm_xor_si128(__m128i a, __m128i b) {
    __m128i r;
    for (int i = 0; i < 16; i++) r.v[i] = a.v[i] ^ b.v[i];
    return r;
}

static inline int _mm_movemask_epi8(__m128i a) {
    int m = 0;
    for (int i = 0; i < 16; i++)
        m |= ((a.v[i] & 0x80) ? 1 : 0) << i;
    return m;
}

#endif // NEON / Fallback

// =========================================================
// Safety Guard: Ensure no x86 macros leaked
// =========================================================
#if defined(__SSE__) || defined(__SSE2__) || defined(__SSE3__) || \
    defined(__SSSE3__) || defined(__SSE4_1__) || defined(__SSE4_2__) || \
    defined(__AVX__)  || defined(__AVX2__)
  #error "x86 SIMD macros must not be defined on ARM64EC build"
#endif

#endif
