#pragma once
#include <cstring>

static inline uint32_t ReadLE32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline uint32_t rol(uint32_t x, int i) { return (x << i) | (x >> (32 - i)); }

static inline uint32_t f1(uint32_t x, uint32_t y, uint32_t z) { return x ^ y ^ z; }
static inline uint32_t f2(uint32_t x, uint32_t y, uint32_t z) { return (x & y) | (~x & z); }
static inline uint32_t f3(uint32_t x, uint32_t y, uint32_t z) { return (x | ~y) ^ z; }
static inline uint32_t f4(uint32_t x, uint32_t y, uint32_t z) { return (x & z) | (y & ~z); }
static inline uint32_t f5(uint32_t x, uint32_t y, uint32_t z) { return x ^ (y | ~z); }

static void Round(uint32_t& a, uint32_t b, uint32_t& c, uint32_t d, uint32_t e,
                  uint32_t f, uint32_t x, uint32_t k, int r) {
    a = rol(a + f + x + k, r) + e;
    c = rol(c, 10);
}

#define R11(a,b,c,d,e,x,r) Round(a,b,c,d,e,f1(b,c,d),x,0,r)
#define R21(a,b,c,d,e,x,r) Round(a,b,c,d,e,f2(b,c,d),x,0x5A827999u,r)
#define R31(a,b,c,d,e,x,r) Round(a,b,c,d,e,f3(b,c,d),x,0x6ED9EBA1u,r)
#define R41(a,b,c,d,e,x,r) Round(a,b,c,d,e,f4(b,c,d),x,0x8F1BBCDCu,r)
#define R51(a,b,c,d,e,x,r) Round(a,b,c,d,e,f5(b,c,d),x,0xA953FD4Eu,r)
#define R12(a,b,c,d,e,x,r) Round(a,b,c,d,e,f5(b,c,d),x,0x50A28BE6u,r)
#define R22(a,b,c,d,e,x,r) Round(a,b,c,d,e,f4(b,c,d),x,0x5C4DD124u,r)
#define R32(a,b,c,d,e,x,r) Round(a,b,c,d,e,f3(b,c,d),x,0x6D703EF3u,r)
#define R42(a,b,c,d,e,x,r) Round(a,b,c,d,e,f2(b,c,d),x,0x7A6D76E9u,r)
#define R52(a,b,c,d,e,x,r) Round(a,b,c,d,e,f1(b,c,d),x,0,r)

static inline void host_ripemd160_transform(uint32_t s[5], const uint8_t chunk[64]) {
    uint32_t a1 = s[0], b1 = s[1], c1 = s[2], d1 = s[3], e1 = s[4];
    uint32_t a2 = a1, b2 = b1, c2 = c1, d2 = d1, e2 = e1;
    uint32_t w[16];
    for (int i = 0; i < 16; ++i) w[i] = ReadLE32(chunk + i * 4);

    R11(a1,b1,c1,d1,e1,w[0],11); R12(a2,b2,c2,d2,e2,w[5],8);
    R11(e1,a1,b1,c1,d1,w[1],14); R12(e2,a2,b2,c2,d2,w[14],9);
    R11(d1,e1,a1,b1,c1,w[2],15); R12(d2,e2,a2,b2,c2,w[7],9);
    R11(c1,d1,e1,a1,b1,w[3],12); R12(c2,d2,e2,a2,b2,w[0],11);
    R11(b1,c1,d1,e1,a1,w[4],5);  R12(b2,c2,d2,e2,a2,w[9],13);
    R11(a1,b1,c1,d1,e1,w[5],8);  R12(a2,b2,c2,d2,e2,w[2],15);
    R11(e1,a1,b1,c1,d1,w[6],7);  R12(e2,a2,b2,c2,d2,w[11],15);
    R11(d1,e1,a1,b1,c1,w[7],9);  R12(d2,e2,a2,b2,c2,w[4],5);
    R11(c1,d1,e1,a1,b1,w[8],11); R12(c2,d2,e2,a2,b2,w[13],7);
    R11(b1,c1,d1,e1,a1,w[9],13); R12(b2,c2,d2,e2,a2,w[6],7);
    R11(a1,b1,c1,d1,e1,w[10],14);R12(a2,b2,c2,d2,e2,w[15],8);
    R11(e1,a1,b1,c1,d1,w[11],15);R12(e2,a2,b2,c2,d2,w[8],11);
    R11(d1,e1,a1,b1,c1,w[12],6); R12(d2,e2,a2,b2,c2,w[1],14);
    R11(c1,d1,e1,a1,b1,w[13],7); R12(c2,d2,e2,a2,b2,w[10],14);
    R11(b1,c1,d1,e1,a1,w[14],9); R12(b2,c2,d2,e2,a2,w[3],12);
    R11(a1,b1,c1,d1,e1,w[15],8); R12(a2,b2,c2,d2,e2,w[12],6);

    R21(e1,a1,b1,c1,d1,w[7],7);  R22(e2,a2,b2,c2,d2,w[6],9);
    R21(d1,e1,a1,b1,c1,w[4],6);  R22(d2,e2,a2,b2,c2,w[11],13);
    R21(c1,d1,e1,a1,b1,w[13],8); R22(c2,d2,e2,a2,b2,w[3],15);
    R21(b1,c1,d1,e1,a1,w[1],13); R22(b2,c2,d2,e2,a2,w[7],7);
    R21(a1,b1,c1,d1,e1,w[10],11);R22(a2,b2,c2,d2,e2,w[0],12);
    R21(e1,a1,b1,c1,d1,w[6],9);  R22(e2,a2,b2,c2,d2,w[13],8);
    R21(d1,e1,a1,b1,c1,w[15],7); R22(d2,e2,a2,b2,c2,w[5],9);
    R21(c1,d1,e1,a1,b1,w[3],15); R22(c2,d2,e2,a2,b2,w[10],11);
    R21(b1,c1,d1,e1,a1,w[12],7); R22(b2,c2,d2,e2,a2,w[14],7);
    R21(a1,b1,c1,d1,e1,w[0],12); R22(a2,b2,c2,d2,e2,w[15],7);
    R21(e1,a1,b1,c1,d1,w[9],15); R22(e2,a2,b2,c2,d2,w[8],12);
    R21(d1,e1,a1,b1,c1,w[5],9);  R22(d2,e2,a2,b2,c2,w[12],7);
    R21(c1,d1,e1,a1,b1,w[2],11); R22(c2,d2,e2,a2,b2,w[4],6);
    R21(b1,c1,d1,e1,a1,w[14],7); R22(b2,c2,d2,e2,a2,w[9],15);
    R21(a1,b1,c1,d1,e1,w[11],13);R22(a2,b2,c2,d2,e2,w[1],13);
    R21(e1,a1,b1,c1,d1,w[8],12); R22(e2,a2,b2,c2,d2,w[2],11);

    R31(d1,e1,a1,b1,c1,w[3],11); R32(d2,e2,a2,b2,c2,w[15],9);
    R31(c1,d1,e1,a1,b1,w[10],13);R32(c2,d2,e2,a2,b2,w[5],7);
    R31(b1,c1,d1,e1,a1,w[14],6); R32(b2,c2,d2,e2,a2,w[1],15);
    R31(a1,b1,c1,d1,e1,w[4],7);  R32(a2,b2,c2,d2,e2,w[3],11);
    R31(e1,a1,b1,c1,d1,w[9],14); R32(e2,a2,b2,c2,d2,w[7],8);
    R31(d1,e1,a1,b1,c1,w[15],9); R32(d2,e2,a2,b2,c2,w[14],6);
    R31(c1,d1,e1,a1,b1,w[8],13); R32(c2,d2,e2,a2,b2,w[6],6);
    R31(b1,c1,d1,e1,a1,w[1],15); R32(b2,c2,d2,e2,a2,w[9],14);
    R31(a1,b1,c1,d1,e1,w[2],14); R32(a2,b2,c2,d2,e2,w[11],12);
    R31(e1,a1,b1,c1,d1,w[7],8);  R32(e2,a2,b2,c2,d2,w[8],13);
    R31(d1,e1,a1,b1,c1,w[0],13); R32(d2,e2,a2,b2,c2,w[12],5);
    R31(c1,d1,e1,a1,b1,w[6],6);  R32(c2,d2,e2,a2,b2,w[2],14);
    R31(b1,c1,d1,e1,a1,w[13],5); R32(b2,c2,d2,e2,a2,w[10],13);
    R31(a1,b1,c1,d1,e1,w[11],12);R32(a2,b2,c2,d2,e2,w[0],13);
    R31(e1,a1,b1,c1,d1,w[5],7);  R32(e2,a2,b2,c2,d2,w[4],7);
    R31(d1,e1,a1,b1,c1,w[12],5); R32(d2,e2,a2,b2,c2,w[13],5);

    R41(c1,d1,e1,a1,b1,w[1],11); R42(c2,d2,e2,a2,b2,w[8],15);
    R41(b1,c1,d1,e1,a1,w[9],12); R42(b2,c2,d2,e2,a2,w[6],5);
    R41(a1,b1,c1,d1,e1,w[11],14);R42(a2,b2,c2,d2,e2,w[4],8);
    R41(e1,a1,b1,c1,d1,w[10],15);R42(e2,a2,b2,c2,d2,w[1],11);
    R41(d1,e1,a1,b1,c1,w[0],14); R42(d2,e2,a2,b2,c2,w[3],14);
    R41(c1,d1,e1,a1,b1,w[8],15); R42(c2,d2,e2,a2,b2,w[11],14);
    R41(b1,c1,d1,e1,a1,w[12],9); R42(b2,c2,d2,e2,a2,w[15],6);
    R41(a1,b1,c1,d1,e1,w[4],8);  R42(a2,b2,c2,d2,e2,w[0],14);
    R41(e1,a1,b1,c1,d1,w[13],9); R42(e2,a2,b2,c2,d2,w[5],6);
    R41(d1,e1,a1,b1,c1,w[3],14); R42(d2,e2,a2,b2,c2,w[12],9);
    R41(c1,d1,e1,a1,b1,w[7],5);  R42(c2,d2,e2,a2,b2,w[2],12);
    R41(b1,c1,d1,e1,a1,w[15],6); R42(b2,c2,d2,e2,a2,w[13],9);
    R41(a1,b1,c1,d1,e1,w[14],8); R42(a2,b2,c2,d2,e2,w[9],12);
    R41(e1,a1,b1,c1,d1,w[5],6);  R42(e2,a2,b2,c2,d2,w[7],5);
    R41(d1,e1,a1,b1,c1,w[6],5);  R42(d2,e2,a2,b2,c2,w[10],15);
    R41(c1,d1,e1,a1,b1,w[2],12); R42(c2,d2,e2,a2,b2,w[14],8);

    R51(b1,c1,d1,e1,a1,w[4],9);  R52(b2,c2,d2,e2,a2,w[12],8);
    R51(a1,b1,c1,d1,e1,w[0],15); R52(a2,b2,c2,d2,e2,w[15],5);
    R51(e1,a1,b1,c1,d1,w[5],5);  R52(e2,a2,b2,c2,d2,w[10],12);
    R51(d1,e1,a1,b1,c1,w[9],11); R52(d2,e2,a2,b2,c2,w[4],9);
    R51(c1,d1,e1,a1,b1,w[7],6);  R52(c2,d2,e2,a2,b2,w[1],12);
    R51(b1,c1,d1,e1,a1,w[12],8); R52(b2,c2,d2,e2,a2,w[5],5);
    R51(a1,b1,c1,d1,e1,w[2],13); R52(a2,b2,c2,d2,e2,w[8],14);
    R51(e1,a1,b1,c1,d1,w[10],12);R52(e2,a2,b2,c2,d2,w[7],6);
    R51(d1,e1,a1,b1,c1,w[14],5); R52(d2,e2,a2,b2,c2,w[6],8);
    R51(c1,d1,e1,a1,b1,w[1],12); R52(c2,d2,e2,a2,b2,w[2],13);
    R51(b1,c1,d1,e1,a1,w[3],13); R52(b2,c2,d2,e2,a2,w[13],6);
    R51(a1,b1,c1,d1,e1,w[8],14); R52(a2,b2,c2,d2,e2,w[14],5);
    R51(e1,a1,b1,c1,d1,w[11],11);R52(e2,a2,b2,c2,d2,w[0],15);
    R51(d1,e1,a1,b1,c1,w[6],8);  R52(d2,e2,a2,b2,c2,w[3],13);
    R51(c1,d1,e1,a1,b1,w[15],5); R52(c2,d2,e2,a2,b2,w[9],11);
    R51(b1,c1,d1,e1,a1,w[13],6); R52(b2,c2,d2,e2,a2,w[11],11);

    uint32_t t = s[0];
    s[0] = s[1] + c1 + d2;
    s[1] = s[2] + d1 + e2;
    s[2] = s[3] + e1 + a2;
    s[3] = s[4] + a1 + b2;
    s[4] = t + b1 + c2;
}

static inline void host_ripemd160(const uint8_t* data, size_t len, uint8_t out[20]) {
    uint32_t s[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    uint8_t buf[64];
    size_t bytes = 0;
    size_t off = 0;
    while (len - off >= 64) {
        host_ripemd160_transform(s, data + off);
        bytes += 64;
        off += 64;
    }
    size_t rem = len - off;
    bytes += rem;
    std::memset(buf, 0, 64);
    if (rem) std::memcpy(buf, data + off, rem);
    buf[rem] = 0x80;
    if (rem >= 56) {
        host_ripemd160_transform(s, buf);
        std::memset(buf, 0, 64);
    }
    uint64_t bits = (uint64_t)bytes * 8;
    for (int i = 0; i < 8; ++i) buf[56 + i] = (uint8_t)(bits >> (8 * i));
    host_ripemd160_transform(s, buf);
    for (int i = 0; i < 5; ++i) {
        out[i * 4]     = (uint8_t)(s[i]);
        out[i * 4 + 1] = (uint8_t)(s[i] >> 8);
        out[i * 4 + 2] = (uint8_t)(s[i] >> 16);
        out[i * 4 + 3] = (uint8_t)(s[i] >> 24);
    }
}
