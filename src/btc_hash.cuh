#pragma once
#include <cstdint>

/* BTC CUDA v2 — SHA256/RIPEMD160 zoptymalizowane pod compressed pubkey (33 B).
 * K w __constant__, mniej byte-packingu, forceinline na hot path. */

__device__ __forceinline__ uint32_t btc_rotr32(uint32_t x, uint32_t n) {
    return __funnelshift_r(x, x, n);
}

__device__ __forceinline__ uint32_t btc_rol32(uint32_t x, int n) {
    return __funnelshift_l(x, x, n);
}

__constant__ uint32_t BTC_SHA256_K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

__device__ __forceinline__ void device_sha256_transform_words(uint32_t state[8], uint32_t w[64]) {
#pragma unroll
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = btc_rotr32(w[i - 15], 7) ^ btc_rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = btc_rotr32(w[i - 2], 17) ^ btc_rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];
#pragma unroll
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = btc_rotr32(e, 6) ^ btc_rotr32(e, 11) ^ btc_rotr32(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + BTC_SHA256_K[i] + w[i];
        uint32_t S0 = btc_rotr32(a, 2) ^ btc_rotr32(a, 13) ^ btc_rotr32(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

/* SHA256( 02/03 || x[32] ) — bez bufora 64 B, W[] z limbów x. */
__device__ __forceinline__ void device_sha256_compressed_x(
    uint32_t xa, uint32_t xb, uint32_t xc, uint32_t xd,
    uint32_t xe, uint32_t xf, uint32_t xg, uint32_t xh,
    uint32_t prefix /* 0x02 or 0x03 */,
    uint32_t out[8]
) {
    uint32_t state[8] = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    };
    uint32_t w[64];
    /* 33 B message + 0x80 + zeros + bitlen 264 (0x108) */
    w[0] = (prefix << 24) | (xa >> 8);
    w[1] = (xa << 24) | (xb >> 8);
    w[2] = (xb << 24) | (xc >> 8);
    w[3] = (xc << 24) | (xd >> 8);
    w[4] = (xd << 24) | (xe >> 8);
    w[5] = (xe << 24) | (xf >> 8);
    w[6] = (xf << 24) | (xg >> 8);
    w[7] = (xg << 24) | (xh >> 8);
    w[8] = (xh << 24) | 0x800000;
    w[9] = 0;
    w[10] = 0;
    w[11] = 0;
    w[12] = 0;
    w[13] = 0;
    w[14] = 0;
    w[15] = 264; /* 33*8 */
    device_sha256_transform_words(state, w);
#pragma unroll
    for (int i = 0; i < 8; i++) out[i] = state[i];
}

__device__ __forceinline__ uint32_t rmd_f1(uint32_t x, uint32_t y, uint32_t z) { return x ^ y ^ z; }
__device__ __forceinline__ uint32_t rmd_f2(uint32_t x, uint32_t y, uint32_t z) { return (x & y) | (~x & z); }
__device__ __forceinline__ uint32_t rmd_f3(uint32_t x, uint32_t y, uint32_t z) { return (x | ~y) ^ z; }
__device__ __forceinline__ uint32_t rmd_f4(uint32_t x, uint32_t y, uint32_t z) { return (x & z) | (y & ~z); }
__device__ __forceinline__ uint32_t rmd_f5(uint32_t x, uint32_t y, uint32_t z) { return x ^ (y | ~z); }

__device__ __forceinline__ void rmd_round_f(
    uint32_t& a, uint32_t b, uint32_t& c, uint32_t d, uint32_t e,
    uint32_t x, uint32_t k, int r, uint32_t f
) {
    a = btc_rol32(a + f + x + k, r) + e;
    c = btc_rol32(c, 10);
}

/* RIPEMD160(SHA256) — SHA words BE → LE message words (bswap). */
__device__ __forceinline__ void device_ripemd160_sha256_words(const uint32_t sha_be[8], uint32_t out20[5]) {
    uint32_t s[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    uint32_t a1 = s[0], b1 = s[1], c1 = s[2], d1 = s[3], e1 = s[4];
    uint32_t a2 = a1, b2 = b1, c2 = c1, d2 = d1, e2 = e1;

    uint32_t w[16];
#pragma unroll
    for (int i = 0; i < 8; i++) w[i] = __byte_perm(sha_be[i], 0, 0x0123); /* bswap32 */
    /* padding jak w device_ripemd160_32: 0x80 @32, bitlen 256 @ bytes 62..63 */
    w[8] = 0x00000080;
    w[9] = 0; w[10] = 0; w[11] = 0; w[12] = 0; w[13] = 0;
    w[14] = 0;
    w[15] = 0x00010000;

#define R1(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0,r,rmd_f1(b,c,d))
#define R2(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0x5A827999u,r,rmd_f2(b,c,d))
#define R3(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0x6ED9EBA1u,r,rmd_f3(b,c,d))
#define R4(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0x8F1BBCDCu,r,rmd_f4(b,c,d))
#define R5(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0xA953FD4Eu,r,rmd_f5(b,c,d))
#define S1(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0x50A28BE6u,r,rmd_f5(b,c,d))
#define S2(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0x5C4DD124u,r,rmd_f4(b,c,d))
#define S3(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0x6D703EF3u,r,rmd_f3(b,c,d))
#define S4(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0x7A6D76E9u,r,rmd_f2(b,c,d))
#define S5(a,b,c,d,e,x,r) rmd_round_f(a,b,c,d,e,x,0,r,rmd_f1(b,c,d))

    R1(a1,b1,c1,d1,e1,w[0],11); S1(a2,b2,c2,d2,e2,w[5],8);
    R1(e1,a1,b1,c1,d1,w[1],14); S1(e2,a2,b2,c2,d2,w[14],9);
    R1(d1,e1,a1,b1,c1,w[2],15); S1(d2,e2,a2,b2,c2,w[7],9);
    R1(c1,d1,e1,a1,b1,w[3],12); S1(c2,d2,e2,a2,b2,w[0],11);
    R1(b1,c1,d1,e1,a1,w[4],5);  S1(b2,c2,d2,e2,a2,w[9],13);
    R1(a1,b1,c1,d1,e1,w[5],8);  S1(a2,b2,c2,d2,e2,w[2],15);
    R1(e1,a1,b1,c1,d1,w[6],7);  S1(e2,a2,b2,c2,d2,w[11],15);
    R1(d1,e1,a1,b1,c1,w[7],9);  S1(d2,e2,a2,b2,c2,w[4],5);
    R1(c1,d1,e1,a1,b1,w[8],11); S1(c2,d2,e2,a2,b2,w[13],7);
    R1(b1,c1,d1,e1,a1,w[9],13); S1(b2,c2,d2,e2,a2,w[6],7);
    R1(a1,b1,c1,d1,e1,w[10],14);S1(a2,b2,c2,d2,e2,w[15],8);
    R1(e1,a1,b1,c1,d1,w[11],15);S1(e2,a2,b2,c2,d2,w[8],11);
    R1(d1,e1,a1,b1,c1,w[12],6); S1(d2,e2,a2,b2,c2,w[1],14);
    R1(c1,d1,e1,a1,b1,w[13],7); S1(c2,d2,e2,a2,b2,w[10],14);
    R1(b1,c1,d1,e1,a1,w[14],9); S1(b2,c2,d2,e2,a2,w[3],12);
    R1(a1,b1,c1,d1,e1,w[15],8); S1(a2,b2,c2,d2,e2,w[12],6);

    R2(e1,a1,b1,c1,d1,w[7],7);  S2(e2,a2,b2,c2,d2,w[6],9);
    R2(d1,e1,a1,b1,c1,w[4],6);  S2(d2,e2,a2,b2,c2,w[11],13);
    R2(c1,d1,e1,a1,b1,w[13],8); S2(c2,d2,e2,a2,b2,w[3],15);
    R2(b1,c1,d1,e1,a1,w[1],13); S2(b2,c2,d2,e2,a2,w[7],7);
    R2(a1,b1,c1,d1,e1,w[10],11);S2(a2,b2,c2,d2,e2,w[0],12);
    R2(e1,a1,b1,c1,d1,w[6],9);  S2(e2,a2,b2,c2,d2,w[13],8);
    R2(d1,e1,a1,b1,c1,w[15],7); S2(d2,e2,a2,b2,c2,w[5],9);
    R2(c1,d1,e1,a1,b1,w[3],15); S2(c2,d2,e2,a2,b2,w[10],11);
    R2(b1,c1,d1,e1,a1,w[12],7); S2(b2,c2,d2,e2,a2,w[14],7);
    R2(a1,b1,c1,d1,e1,w[0],12); S2(a2,b2,c2,d2,e2,w[15],7);
    R2(e1,a1,b1,c1,d1,w[9],15); S2(e2,a2,b2,c2,d2,w[8],12);
    R2(d1,e1,a1,b1,c1,w[5],9);  S2(d2,e2,a2,b2,c2,w[12],7);
    R2(c1,d1,e1,a1,b1,w[2],11); S2(c2,d2,e2,a2,b2,w[4],6);
    R2(b1,c1,d1,e1,a1,w[14],7); S2(b2,c2,d2,e2,a2,w[9],15);
    R2(a1,b1,c1,d1,e1,w[11],13);S2(a2,b2,c2,d2,e2,w[1],13);
    R2(e1,a1,b1,c1,d1,w[8],12); S2(e2,a2,b2,c2,d2,w[2],11);

    R3(d1,e1,a1,b1,c1,w[3],11); S3(d2,e2,a2,b2,c2,w[15],9);
    R3(c1,d1,e1,a1,b1,w[10],13);S3(c2,d2,e2,a2,b2,w[5],7);
    R3(b1,c1,d1,e1,a1,w[14],6); S3(b2,c2,d2,e2,a2,w[1],15);
    R3(a1,b1,c1,d1,e1,w[4],7);  S3(a2,b2,c2,d2,e2,w[3],11);
    R3(e1,a1,b1,c1,d1,w[9],14); S3(e2,a2,b2,c2,d2,w[7],8);
    R3(d1,e1,a1,b1,c1,w[15],9); S3(d2,e2,a2,b2,c2,w[14],6);
    R3(c1,d1,e1,a1,b1,w[8],13); S3(c2,d2,e2,a2,b2,w[6],6);
    R3(b1,c1,d1,e1,a1,w[1],15); S3(b2,c2,d2,e2,a2,w[9],14);
    R3(a1,b1,c1,d1,e1,w[2],14); S3(a2,b2,c2,d2,e2,w[11],12);
    R3(e1,a1,b1,c1,d1,w[7],8);  S3(e2,a2,b2,c2,d2,w[8],13);
    R3(d1,e1,a1,b1,c1,w[0],13); S3(d2,e2,a2,b2,c2,w[12],5);
    R3(c1,d1,e1,a1,b1,w[6],6);  S3(c2,d2,e2,a2,b2,w[2],14);
    R3(b1,c1,d1,e1,a1,w[13],5); S3(b2,c2,d2,e2,a2,w[10],13);
    R3(a1,b1,c1,d1,e1,w[11],12);S3(a2,b2,c2,d2,e2,w[0],13);
    R3(e1,a1,b1,c1,d1,w[5],7);  S3(e2,a2,b2,c2,d2,w[4],7);
    R3(d1,e1,a1,b1,c1,w[12],5); S3(d2,e2,a2,b2,c2,w[13],5);

    R4(c1,d1,e1,a1,b1,w[1],11); S4(c2,d2,e2,a2,b2,w[8],15);
    R4(b1,c1,d1,e1,a1,w[9],12); S4(b2,c2,d2,e2,a2,w[6],5);
    R4(a1,b1,c1,d1,e1,w[11],14);S4(a2,b2,c2,d2,e2,w[4],8);
    R4(e1,a1,b1,c1,d1,w[10],15);S4(e2,a2,b2,c2,d2,w[1],11);
    R4(d1,e1,a1,b1,c1,w[0],14); S4(d2,e2,a2,b2,c2,w[3],14);
    R4(c1,d1,e1,a1,b1,w[8],15); S4(c2,d2,e2,a2,b2,w[11],14);
    R4(b1,c1,d1,e1,a1,w[12],9); S4(b2,c2,d2,e2,a2,w[15],6);
    R4(a1,b1,c1,d1,e1,w[4],8);  S4(a2,b2,c2,d2,e2,w[0],14);
    R4(e1,a1,b1,c1,d1,w[13],9); S4(e2,a2,b2,c2,d2,w[5],6);
    R4(d1,e1,a1,b1,c1,w[3],14); S4(d2,e2,a2,b2,c2,w[12],9);
    R4(c1,d1,e1,a1,b1,w[7],5);  S4(c2,d2,e2,a2,b2,w[2],12);
    R4(b1,c1,d1,e1,a1,w[15],6); S4(b2,c2,d2,e2,a2,w[13],9);
    R4(a1,b1,c1,d1,e1,w[14],8); S4(a2,b2,c2,d2,e2,w[9],12);
    R4(e1,a1,b1,c1,d1,w[5],6);  S4(e2,a2,b2,c2,d2,w[7],5);
    R4(d1,e1,a1,b1,c1,w[6],5);  S4(d2,e2,a2,b2,c2,w[10],15);
    R4(c1,d1,e1,a1,b1,w[2],12); S4(c2,d2,e2,a2,b2,w[14],8);

    R5(b1,c1,d1,e1,a1,w[4],9);  S5(b2,c2,d2,e2,a2,w[12],8);
    R5(a1,b1,c1,d1,e1,w[0],15); S5(a2,b2,c2,d2,e2,w[15],5);
    R5(e1,a1,b1,c1,d1,w[5],5);  S5(e2,a2,b2,c2,d2,w[10],12);
    R5(d1,e1,a1,b1,c1,w[9],11); S5(d2,e2,a2,b2,c2,w[4],9);
    R5(c1,d1,e1,a1,b1,w[7],6);  S5(c2,d2,e2,a2,b2,w[1],12);
    R5(b1,c1,d1,e1,a1,w[12],8); S5(b2,c2,d2,e2,a2,w[5],5);
    R5(a1,b1,c1,d1,e1,w[2],13); S5(a2,b2,c2,d2,e2,w[8],14);
    R5(e1,a1,b1,c1,d1,w[10],12);S5(e2,a2,b2,c2,d2,w[7],6);
    R5(d1,e1,a1,b1,c1,w[14],5); S5(d2,e2,a2,b2,c2,w[6],8);
    R5(c1,d1,e1,a1,b1,w[1],12); S5(c2,d2,e2,a2,b2,w[2],13);
    R5(b1,c1,d1,e1,a1,w[3],13); S5(b2,c2,d2,e2,a2,w[13],6);
    R5(a1,b1,c1,d1,e1,w[8],14); S5(a2,b2,c2,d2,e2,w[14],5);
    R5(e1,a1,b1,c1,d1,w[11],11);S5(e2,a2,b2,c2,d2,w[0],15);
    R5(d1,e1,a1,b1,c1,w[6],8);  S5(d2,e2,a2,b2,c2,w[3],13);
    R5(c1,d1,e1,a1,b1,w[15],5); S5(c2,d2,e2,a2,b2,w[9],11);
    R5(b1,c1,d1,e1,a1,w[13],6); S5(b2,c2,d2,e2,a2,w[11],11);

#undef R1
#undef R2
#undef R3
#undef R4
#undef R5
#undef S1
#undef S2
#undef S3
#undef S4
#undef S5

    uint32_t t = s[0];
    s[0] = s[1] + c1 + d2;
    s[1] = s[2] + d1 + e2;
    s[2] = s[3] + e1 + a2;
    s[3] = s[4] + a1 + b2;
    s[4] = t + b1 + c2;

    /* RIPEMD state is LE; Address uses BE-ish packing like before via bytes20 */
    out20[0] = s[0];
    out20[1] = s[1];
    out20[2] = s[2];
    out20[3] = s[3];
    out20[4] = s[4];
}

/* Legacy wrappers — zachowane dla kompatybilnosci / testow */
__device__ void device_sha256_transform(uint32_t state[8], const uint8_t block[64]) {
    uint32_t w[64];
#pragma unroll
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)block[i * 4] << 24) | ((uint32_t)block[i * 4 + 1] << 16) |
               ((uint32_t)block[i * 4 + 2] << 8) | block[i * 4 + 3];
    }
    device_sha256_transform_words(state, w);
}

__device__ void device_sha256_33(const uint8_t msg[33], uint8_t out[32]) {
    uint32_t state[8] = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    };
    uint8_t block[64];
#pragma unroll
    for (int i = 0; i < 64; i++) block[i] = 0;
#pragma unroll
    for (int i = 0; i < 33; i++) block[i] = msg[i];
    block[33] = 0x80;
    block[62] = 0x01;
    block[63] = 0x08;
    device_sha256_transform(state, block);
#pragma unroll
    for (int i = 0; i < 8; i++) {
        out[i * 4]     = (uint8_t)(state[i] >> 24);
        out[i * 4 + 1] = (uint8_t)(state[i] >> 16);
        out[i * 4 + 2] = (uint8_t)(state[i] >> 8);
        out[i * 4 + 3] = (uint8_t)(state[i]);
    }
}

__device__ __forceinline__ uint32_t rmd_read_le32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

__device__ void device_ripemd160_32(const uint8_t msg[32], uint8_t out[20]) {
    uint32_t sha_be[8];
#pragma unroll
    for (int i = 0; i < 8; i++) {
        sha_be[i] = ((uint32_t)msg[i * 4] << 24) | ((uint32_t)msg[i * 4 + 1] << 16) |
                    ((uint32_t)msg[i * 4 + 2] << 8) | (uint32_t)msg[i * 4 + 3];
    }
    uint32_t r[5];
    device_ripemd160_sha256_words(sha_be, r);
#pragma unroll
    for (int i = 0; i < 5; i++) {
        out[i * 4]     = (uint8_t)(r[i]);
        out[i * 4 + 1] = (uint8_t)(r[i] >> 8);
        out[i * 4 + 2] = (uint8_t)(r[i] >> 16);
        out[i * 4 + 3] = (uint8_t)(r[i] >> 24);
    }
}
