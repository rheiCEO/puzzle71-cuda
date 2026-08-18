
#pragma once
#include <cstdint>

__device__ __forceinline__ uint32_t btc_rotr32(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32 - n));
}

__device__ __forceinline__ uint32_t btc_rol32(uint32_t x, int n) {
    return (x << n) | (x >> (32 - n));
}

__device__ void device_sha256_transform(uint32_t state[8], const uint8_t block[64]) {
    static const uint32_t K[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    };
    uint32_t w[64];
#pragma unroll
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)block[i * 4] << 24) | ((uint32_t)block[i * 4 + 1] << 16) |
               ((uint32_t)block[i * 4 + 2] << 8) | block[i * 4 + 3];
    }
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
        uint32_t t1 = h + S1 + ch + K[i] + w[i];
        uint32_t S0 = btc_rotr32(a, 2) ^ btc_rotr32(a, 13) ^ btc_rotr32(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
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

__device__ void rmd_round(uint32_t& a, uint32_t b, uint32_t& c, uint32_t d, uint32_t e,
                          uint32_t (*f)(uint32_t, uint32_t, uint32_t), uint32_t x, uint32_t k, int r) {
    a = btc_rol32(a + f(b, c, d) + x + k, r) + e;
    c = btc_rol32(c, 10);
}

__device__ __forceinline__ uint32_t rmd_f1(uint32_t x, uint32_t y, uint32_t z) { return x ^ y ^ z; }
__device__ __forceinline__ uint32_t rmd_f2(uint32_t x, uint32_t y, uint32_t z) { return (x & y) | (~x & z); }
__device__ __forceinline__ uint32_t rmd_f3(uint32_t x, uint32_t y, uint32_t z) { return (x | ~y) ^ z; }
__device__ __forceinline__ uint32_t rmd_f4(uint32_t x, uint32_t y, uint32_t z) { return (x & z) | (y & ~z); }
__device__ __forceinline__ uint32_t rmd_f5(uint32_t x, uint32_t y, uint32_t z) { return x ^ (y | ~z); }

__device__ void device_ripemd160_transform(uint32_t s[5], const uint8_t chunk[64]) {
    uint32_t a1 = s[0], b1 = s[1], c1 = s[2], d1 = s[3], e1 = s[4];
    uint32_t a2 = a1, b2 = b1, c2 = c1, d2 = d1, e2 = e1;
    uint32_t w[16];
#pragma unroll
    for (int i = 0; i < 16; i++) w[i] = rmd_read_le32(chunk + i * 4);

#define BTC_R11(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f1,x,0,r)
#define BTC_R21(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f2,x,0x5A827999u,r)
#define BTC_R31(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f3,x,0x6ED9EBA1u,r)
#define BTC_R41(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f4,x,0x8F1BBCDCu,r)
#define BTC_R51(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f5,x,0xA953FD4Eu,r)
#define BTC_R12(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f5,x,0x50A28BE6u,r)
#define BTC_R22(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f4,x,0x5C4DD124u,r)
#define BTC_R32(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f3,x,0x6D703EF3u,r)
#define BTC_R42(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f2,x,0x7A6D76E9u,r)
#define BTC_R52(a,b,c,d,e,x,r) rmd_round(a,b,c,d,e,rmd_f1,x,0,r)

    BTC_R11(a1,b1,c1,d1,e1,w[0],11); BTC_R12(a2,b2,c2,d2,e2,w[5],8);
    BTC_R11(e1,a1,b1,c1,d1,w[1],14); BTC_R12(e2,a2,b2,c2,d2,w[14],9);
    BTC_R11(d1,e1,a1,b1,c1,w[2],15); BTC_R12(d2,e2,a2,b2,c2,w[7],9);
    BTC_R11(c1,d1,e1,a1,b1,w[3],12); BTC_R12(c2,d2,e2,a2,b2,w[0],11);
    BTC_R11(b1,c1,d1,e1,a1,w[4],5);  BTC_R12(b2,c2,d2,e2,a2,w[9],13);
    BTC_R11(a1,b1,c1,d1,e1,w[5],8);  BTC_R12(a2,b2,c2,d2,e2,w[2],15);
    BTC_R11(e1,a1,b1,c1,d1,w[6],7);  BTC_R12(e2,a2,b2,c2,d2,w[11],15);
    BTC_R11(d1,e1,a1,b1,c1,w[7],9);  BTC_R12(d2,e2,a2,b2,c2,w[4],5);
    BTC_R11(c1,d1,e1,a1,b1,w[8],11); BTC_R12(c2,d2,e2,a2,b2,w[13],7);
    BTC_R11(b1,c1,d1,e1,a1,w[9],13); BTC_R12(b2,c2,d2,e2,a2,w[6],7);
    BTC_R11(a1,b1,c1,d1,e1,w[10],14);BTC_R12(a2,b2,c2,d2,e2,w[15],8);
    BTC_R11(e1,a1,b1,c1,d1,w[11],15);BTC_R12(e2,a2,b2,c2,d2,w[8],11);
    BTC_R11(d1,e1,a1,b1,c1,w[12],6); BTC_R12(d2,e2,a2,b2,c2,w[1],14);
    BTC_R11(c1,d1,e1,a1,b1,w[13],7); BTC_R12(c2,d2,e2,a2,b2,w[10],14);
    BTC_R11(b1,c1,d1,e1,a1,w[14],9); BTC_R12(b2,c2,d2,e2,a2,w[3],12);
    BTC_R11(a1,b1,c1,d1,e1,w[15],8); BTC_R12(a2,b2,c2,d2,e2,w[12],6);

    BTC_R21(e1,a1,b1,c1,d1,w[7],7);  BTC_R22(e2,a2,b2,c2,d2,w[6],9);
    BTC_R21(d1,e1,a1,b1,c1,w[4],6);  BTC_R22(d2,e2,a2,b2,c2,w[11],13);
    BTC_R21(c1,d1,e1,a1,b1,w[13],8); BTC_R22(c2,d2,e2,a2,b2,w[3],15);
    BTC_R21(b1,c1,d1,e1,a1,w[1],13); BTC_R22(b2,c2,d2,e2,a2,w[7],7);
    BTC_R21(a1,b1,c1,d1,e1,w[10],11);BTC_R22(a2,b2,c2,d2,e2,w[0],12);
    BTC_R21(e1,a1,b1,c1,d1,w[6],9);  BTC_R22(e2,a2,b2,c2,d2,w[13],8);
    BTC_R21(d1,e1,a1,b1,c1,w[15],7); BTC_R22(d2,e2,a2,b2,c2,w[5],9);
    BTC_R21(c1,d1,e1,a1,b1,w[3],15); BTC_R22(c2,d2,e2,a2,b2,w[10],11);
    BTC_R21(b1,c1,d1,e1,a1,w[12],7); BTC_R22(b2,c2,d2,e2,a2,w[14],7);
    BTC_R21(a1,b1,c1,d1,e1,w[0],12); BTC_R22(a2,b2,c2,d2,e2,w[15],7);
    BTC_R21(e1,a1,b1,c1,d1,w[9],15); BTC_R22(e2,a2,b2,c2,d2,w[8],12);
    BTC_R21(d1,e1,a1,b1,c1,w[5],9);  BTC_R22(d2,e2,a2,b2,c2,w[12],7);
    BTC_R21(c1,d1,e1,a1,b1,w[2],11); BTC_R22(c2,d2,e2,a2,b2,w[4],6);
    BTC_R21(b1,c1,d1,e1,a1,w[14],7); BTC_R22(b2,c2,d2,e2,a2,w[9],15);
    BTC_R21(a1,b1,c1,d1,e1,w[11],13);BTC_R22(a2,b2,c2,d2,e2,w[1],13);
    BTC_R21(e1,a1,b1,c1,d1,w[8],12); BTC_R22(e2,a2,b2,c2,d2,w[2],11);

    BTC_R31(d1,e1,a1,b1,c1,w[3],11); BTC_R32(d2,e2,a2,b2,c2,w[15],9);
    BTC_R31(c1,d1,e1,a1,b1,w[10],13);BTC_R32(c2,d2,e2,a2,b2,w[5],7);
    BTC_R31(b1,c1,d1,e1,a1,w[14],6); BTC_R32(b2,c2,d2,e2,a2,w[1],15);
    BTC_R31(a1,b1,c1,d1,e1,w[4],7);  BTC_R32(a2,b2,c2,d2,e2,w[3],11);
    BTC_R31(e1,a1,b1,c1,d1,w[9],14); BTC_R32(e2,a2,b2,c2,d2,w[7],8);
    BTC_R31(d1,e1,a1,b1,c1,w[15],9); BTC_R32(d2,e2,a2,b2,c2,w[14],6);
    BTC_R31(c1,d1,e1,a1,b1,w[8],13); BTC_R32(c2,d2,e2,a2,b2,w[6],6);
    BTC_R31(b1,c1,d1,e1,a1,w[1],15); BTC_R32(b2,c2,d2,e2,a2,w[9],14);
    BTC_R31(a1,b1,c1,d1,e1,w[2],14); BTC_R32(a2,b2,c2,d2,e2,w[11],12);
    BTC_R31(e1,a1,b1,c1,d1,w[7],8);  BTC_R32(e2,a2,b2,c2,d2,w[8],13);
    BTC_R31(d1,e1,a1,b1,c1,w[0],13); BTC_R32(d2,e2,a2,b2,c2,w[12],5);
    BTC_R31(c1,d1,e1,a1,b1,w[6],6);  BTC_R32(c2,d2,e2,a2,b2,w[2],14);
    BTC_R31(b1,c1,d1,e1,a1,w[13],5); BTC_R32(b2,c2,d2,e2,a2,w[10],13);
    BTC_R31(a1,b1,c1,d1,e1,w[11],12);BTC_R32(a2,b2,c2,d2,e2,w[0],13);
    BTC_R31(e1,a1,b1,c1,d1,w[5],7);  BTC_R32(e2,a2,b2,c2,d2,w[4],7);
    BTC_R31(d1,e1,a1,b1,c1,w[12],5); BTC_R32(d2,e2,a2,b2,c2,w[13],5);

    BTC_R41(c1,d1,e1,a1,b1,w[1],11); BTC_R42(c2,d2,e2,a2,b2,w[8],15);
    BTC_R41(b1,c1,d1,e1,a1,w[9],12); BTC_R42(b2,c2,d2,e2,a2,w[6],5);
    BTC_R41(a1,b1,c1,d1,e1,w[11],14);BTC_R42(a2,b2,c2,d2,e2,w[4],8);
    BTC_R41(e1,a1,b1,c1,d1,w[10],15);BTC_R42(e2,a2,b2,c2,d2,w[1],11);
    BTC_R41(d1,e1,a1,b1,c1,w[0],14); BTC_R42(d2,e2,a2,b2,c2,w[3],14);
    BTC_R41(c1,d1,e1,a1,b1,w[8],15); BTC_R42(c2,d2,e2,a2,b2,w[11],14);
    BTC_R41(b1,c1,d1,e1,a1,w[12],9); BTC_R42(b2,c2,d2,e2,a2,w[15],6);
    BTC_R41(a1,b1,c1,d1,e1,w[4],8);  BTC_R42(a2,b2,c2,d2,e2,w[0],14);
    BTC_R41(e1,a1,b1,c1,d1,w[13],9); BTC_R42(e2,a2,b2,c2,d2,w[5],6);
    BTC_R41(d1,e1,a1,b1,c1,w[3],14); BTC_R42(d2,e2,a2,b2,c2,w[12],9);
    BTC_R41(c1,d1,e1,a1,b1,w[7],5);  BTC_R42(c2,d2,e2,a2,b2,w[2],12);
    BTC_R41(b1,c1,d1,e1,a1,w[15],6); BTC_R42(b2,c2,d2,e2,a2,w[13],9);
    BTC_R41(a1,b1,c1,d1,e1,w[14],8); BTC_R42(a2,b2,c2,d2,e2,w[9],12);
    BTC_R41(e1,a1,b1,c1,d1,w[5],6);  BTC_R42(e2,a2,b2,c2,d2,w[7],5);
    BTC_R41(d1,e1,a1,b1,c1,w[6],5);  BTC_R42(d2,e2,a2,b2,c2,w[10],15);
    BTC_R41(c1,d1,e1,a1,b1,w[2],12); BTC_R42(c2,d2,e2,a2,b2,w[14],8);

    BTC_R51(b1,c1,d1,e1,a1,w[4],9);  BTC_R52(b2,c2,d2,e2,a2,w[12],8);
    BTC_R51(a1,b1,c1,d1,e1,w[0],15); BTC_R52(a2,b2,c2,d2,e2,w[15],5);
    BTC_R51(e1,a1,b1,c1,d1,w[5],5);  BTC_R52(e2,a2,b2,c2,d2,w[10],12);
    BTC_R51(d1,e1,a1,b1,c1,w[9],11); BTC_R52(d2,e2,a2,b2,c2,w[4],9);
    BTC_R51(c1,d1,e1,a1,b1,w[7],6);  BTC_R52(c2,d2,e2,a2,b2,w[1],12);
    BTC_R51(b1,c1,d1,e1,a1,w[12],8); BTC_R52(b2,c2,d2,e2,a2,w[5],5);
    BTC_R51(a1,b1,c1,d1,e1,w[2],13); BTC_R52(a2,b2,c2,d2,e2,w[8],14);
    BTC_R51(e1,a1,b1,c1,d1,w[10],12);BTC_R52(e2,a2,b2,c2,d2,w[7],6);
    BTC_R51(d1,e1,a1,b1,c1,w[14],5); BTC_R52(d2,e2,a2,b2,c2,w[6],8);
    BTC_R51(c1,d1,e1,a1,b1,w[1],12); BTC_R52(c2,d2,e2,a2,b2,w[2],13);
    BTC_R51(b1,c1,d1,e1,a1,w[3],13); BTC_R52(b2,c2,d2,e2,a2,w[13],6);
    BTC_R51(a1,b1,c1,d1,e1,w[8],14); BTC_R52(a2,b2,c2,d2,e2,w[14],5);
    BTC_R51(e1,a1,b1,c1,d1,w[11],11);BTC_R52(e2,a2,b2,c2,d2,w[0],15);
    BTC_R51(d1,e1,a1,b1,c1,w[6],8);  BTC_R52(d2,e2,a2,b2,c2,w[3],13);
    BTC_R51(c1,d1,e1,a1,b1,w[15],5); BTC_R52(c2,d2,e2,a2,b2,w[9],11);
    BTC_R51(b1,c1,d1,e1,a1,w[13],6); BTC_R52(b2,c2,d2,e2,a2,w[11],11);

#undef BTC_R11
#undef BTC_R21
#undef BTC_R31
#undef BTC_R41
#undef BTC_R51
#undef BTC_R12
#undef BTC_R22
#undef BTC_R32
#undef BTC_R42
#undef BTC_R52

    uint32_t t = s[0];
    s[0] = s[1] + c1 + d2;
    s[1] = s[2] + d1 + e2;
    s[2] = s[3] + e1 + a2;
    s[3] = s[4] + a1 + b2;
    s[4] = t + b1 + c2;
}

__device__ void device_ripemd160_32(const uint8_t msg[32], uint8_t out[20]) {
    uint32_t s[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    uint8_t block[64];
#pragma unroll
    for (int i = 0; i < 64; i++) block[i] = 0;
#pragma unroll
    for (int i = 0; i < 32; i++) block[i] = msg[i];
    block[32] = 0x80;
    block[62] = 0x01;
    block[63] = 0x00;
    device_ripemd160_transform(s, block);
#pragma unroll
    for (int i = 0; i < 5; i++) {
        out[i * 4]     = (uint8_t)(s[i]);
        out[i * 4 + 1] = (uint8_t)(s[i] >> 8);
        out[i * 4 + 2] = (uint8_t)(s[i] >> 16);
        out[i * 4 + 3] = (uint8_t)(s[i] >> 24);
    }
}
