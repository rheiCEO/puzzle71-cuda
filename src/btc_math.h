
#pragma once
#include "structures.h"
#include "btc_hash.cuh"


__device__ __forceinline__ void uint256_x_to_be32(const _uint256& x, uint8_t out[32]) {
    const uint32_t w[8] = {x.a, x.b, x.c, x.d, x.e, x.f, x.g, x.h};
#pragma unroll
    for (int i = 0; i < 8; i++) {
        out[i * 4]     = (uint8_t)(w[i] >> 24);
        out[i * 4 + 1] = (uint8_t)(w[i] >> 16);
        out[i * 4 + 2] = (uint8_t)(w[i] >> 8);
        out[i * 4 + 3] = (uint8_t)(w[i]);
    }
}


__device__ __forceinline__ Address bytes20_to_address(const uint8_t b[20]) {
    return Address{
        ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | (uint32_t)b[3],
        ((uint32_t)b[4] << 24) | ((uint32_t)b[5] << 16) | ((uint32_t)b[6] << 8) | (uint32_t)b[7],
        ((uint32_t)b[8] << 24) | ((uint32_t)b[9] << 16) | ((uint32_t)b[10] << 8) | (uint32_t)b[11],
        ((uint32_t)b[12] << 24) | ((uint32_t)b[13] << 16) | ((uint32_t)b[14] << 8) | (uint32_t)b[15],
        ((uint32_t)b[16] << 24) | ((uint32_t)b[17] << 16) | ((uint32_t)b[18] << 8) | (uint32_t)b[19]
    };
}


__device__ __forceinline__ Address calculate_hash160_compressed(_uint256 x, _uint256 y) {
    uint8_t pub[33];
    pub[0] = (y.h & 1) ? 0x03 : 0x02;
    uint256_x_to_be32(x, pub + 1);
    uint8_t sha[32];
    device_sha256_33(pub, sha);
    uint8_t rmd[20];
    device_ripemd160_32(sha, rmd);
    return bytes20_to_address(rmd);
}
