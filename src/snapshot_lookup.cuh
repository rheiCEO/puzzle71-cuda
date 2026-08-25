#pragma once
#include "structures.h"

/* Binary search posortowanej tablicy hash160 (Address, 20 B) w VRAM. */

__device__ __forceinline__ int address_cmp(Address x, Address y) {
    if (x.a != y.a) return (x.a > y.a) ? 1 : -1;
    if (x.b != y.b) return (x.b > y.b) ? 1 : -1;
    if (x.c != y.c) return (x.c > y.c) ? 1 : -1;
    if (x.d != y.d) return (x.d > y.d) ? 1 : -1;
    if (x.e != y.e) return (x.e > y.e) ? 1 : -1;
    return 0;
}

__device__ __forceinline__ bool snapshot_contains(Address a, const Address* table, uint64_t n) {
    uint64_t lo = 0;
    uint64_t hi = n;
    while (lo < hi) {
        uint64_t mid = (lo + hi) >> 1;
        Address t = table[mid];
        int c = address_cmp(a, t);
        if (c == 0) return true;
        if (c < 0) hi = mid;
        else lo = mid + 1;
    }
    return false;
}
