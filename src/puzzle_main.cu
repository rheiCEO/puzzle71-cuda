/*
 * puzzle71-cuda — Bitcoin Puzzle #71 GPU solver (BTC CUDA v2)
 * Based on eth-vanity-cuda (Manuel, AGPL-3.0) — secp256k1 batch + hash160
 * v2/magic: fused hash160 + specialized puzzle kernel + ping-pong offsets
 */

#if defined(_WIN64)
    #define WIN32_NO_STATUS
    #include <windows.h>
    #undef WIN32_NO_STATUS
#endif

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cuda_runtime.h>

#include "structures.h"
#include "cpu_math.h"
#include "cpu_curve_math.h"
#include "cpu_btc_hash.h"
#include "secure_rand.h"

enum class SearchMode { Sequential, Random };

#define DEFAULT_CHECKPOINT "puzzle71.progress"

#define OUTPUT_BUFFER_SIZE 256
#define BLOCK_SIZE 256U
#define THREAD_WORK (1U << 8)

__constant__ CurvePoint thread_offsets[BLOCK_SIZE];
__constant__ CurvePoint addends[THREAD_WORK - 1];
__constant__ uint32_t device_target[5];
__device__ uint64_t device_memory[2 + OUTPUT_BUFFER_SIZE * 3];

#ifdef __linux__
    #define atomicMax_ul(a, b) atomicMax((unsigned long long*)(a), (unsigned long long)(b))
    #define atomicAdd_ul(a, b) atomicAdd((unsigned long long*)(a), (unsigned long long)(b))
#else
    #define atomicMax_ul(a, b) atomicMax(a, b)
    #define atomicAdd_ul(a, b) atomicAdd(a, b)
#endif

__device__ int count_zero_bytes(uint32_t x) {
    int n = 0;
    n += ((x & 0xFF) == 0);
    n += ((x & 0xFF00) == 0);
    n += ((x & 0xFF0000) == 0);
    n += ((x & 0xFF000000) == 0);
    return n;
}

__device__ int score_zero_bytes(Address a) {
    return count_zero_bytes(a.a) + count_zero_bytes(a.b) + count_zero_bytes(a.c)
         + count_zero_bytes(a.d) + count_zero_bytes(a.e);
}

__device__ int score_leading_zeros(Address a) {
    int n = __clz(a.a);
    if (n == 32) {
        n += __clz(a.b);
        if (n == 64) {
            n += __clz(a.c);
            if (n == 96) {
                n += __clz(a.d);
                if (n == 128) n += __clz(a.e);
            }
        }
    }
    return n >> 3;
}

__device__ bool hash160_matches_target(Address a) {
    return a.a == device_target[0] && a.b == device_target[1] && a.c == device_target[2]
        && a.d == device_target[3] && a.e == device_target[4];
}

__device__ void handle_output(int score_method, Address a, uint64_t key, bool /*inv*/) {
    if (score_method == 3) {
        if (!hash160_matches_target(a)) return;
        uint32_t idx = atomicAdd_ul(&device_memory[0], 1);
        if (idx < OUTPUT_BUFFER_SIZE) {
            device_memory[2 + idx] = key;
            device_memory[OUTPUT_BUFFER_SIZE + 2 + idx] = 1;
            device_memory[OUTPUT_BUFFER_SIZE * 2 + 2 + idx] = 0;
        }
        return;
    }

    int score = 0;
    if (score_method == 0) score = score_leading_zeros(a);
    else if (score_method == 1) score = score_zero_bytes(a);

    if (score >= device_memory[1]) {
        atomicMax_ul(&device_memory[1], score);
        if (score >= device_memory[1]) {
            uint32_t idx = atomicAdd_ul(&device_memory[0], 1);
            if (idx < OUTPUT_BUFFER_SIZE) {
                device_memory[2 + idx] = key;
                device_memory[OUTPUT_BUFFER_SIZE + 2 + idx] = score;
                device_memory[OUTPUT_BUFFER_SIZE * 2 + 2 + idx] = 0;
            }
        }
    }
}

#include "btc_address.h"

#define CUDA_CHECK(call) do { \
    cudaError_t _e = (call); \
    if (_e != cudaSuccess) { \
        std::fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__, cudaGetErrorString(_e)); \
        return 1; \
    } \
} while (0)

static uint32_t hex_nibble(char c) {
    if (c >= '0' && c <= '9') return (uint32_t)(c - '0');
    if (c >= 'a' && c <= 'f') return (uint32_t)(c - 'a' + 10);
    if (c >= 'A' && c <= 'F') return (uint32_t)(c - 'A' + 10);
    return 0;
}

static _uint256 parse_hex_uint256(const char* s) {
    char hex[65];
    std::memset(hex, '0', 64);
    hex[64] = '\0';
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    size_t len = std::strlen(s);
    if (len > 64) len = 64;
    std::memcpy(hex + (64 - len), s, len);
    _uint256 r{};
    uint32_t* words[8] = {&r.a, &r.b, &r.c, &r.d, &r.e, &r.f, &r.g, &r.h};
    for (int i = 0; i < 8; i++) {
        uint32_t w = 0;
        for (int j = 0; j < 8; j++)
            w = (w << 4) | hex_nibble(hex[i * 8 + j]);
        *words[i] = w;
    }
    return r;
}

static Address parse_hash160_hex(const char* s) {
    char hex[41];
    std::memset(hex, '0', 40);
    hex[40] = '\0';
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    size_t len = std::strlen(s);
    if (len > 40) len = 40;
    std::memcpy(hex + (40 - len), s, len);
    uint8_t b[20];
    for (int i = 0; i < 20; i++)
        b[i] = (uint8_t)((hex_nibble(hex[i * 2]) << 4) | hex_nibble(hex[i * 2 + 1]));
    return host_bytes20_to_address(b);
}

static void format_uint256_hex(const _uint256& k, char* out, size_t cap) {
    std::snprintf(out, cap, "%08x%08x%08x%08x%08x%08x%08x%08x",
        k.a, k.b, k.c, k.d, k.e, k.f, k.g, k.h);
}

static void format_address_hex(const Address& a, char* out, size_t cap) {
    std::snprintf(out, cap, "%08x%08x%08x%08x%08x", a.a, a.b, a.c, a.d, a.e);
}

static uint64_t ms_now() {
    return (uint64_t)std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

static uint32_t read_work_scale(int argc, char** argv) {
    for (int i = 1; i + 1 < argc; i++) {
        if (std::strcmp(argv[i], "--work-scale") == 0) {
            int v = std::atoi(argv[i + 1]);
            if (v >= 10 && v <= 20) return (uint32_t)v;
        }
    }
    const char* env = std::getenv("PUZZLE71_WORK_SCALE");
    if (env && env[0]) {
        int v = std::atoi(env);
        if (v >= 10 && v <= 20) return (uint32_t)v;
    }
    return 16;
}


static _uint256 random_base_in_range(_uint256 start, _uint256 end, _uint256 key_increment) {
    if (gt_256(start, end)) return start;
    _uint256 max_base;
    if (gte_256(key_increment, end)) {
        max_base = start;
    } else {
        max_base = cpu_sub_256(end, key_increment);
        if (gt_256(start, max_base)) return start;
    }
    _uint256 span = cpu_sub_256(max_base, start);
    if (eqeq_256(span, _uint256{0, 0, 0, 0, 0, 0, 0, 0})) return start;
    _uint256 offset{};
    if (generate_secure_random_key(offset, span, 72) != 0) return start;
    return cpu_add_256(start, offset);
}

static bool save_checkpoint(const char* path, SearchMode mode,
    const _uint256& start, const _uint256& end, const Address& target,
    const _uint256& base_key, uint64_t total_keys) {
    FILE* f = std::fopen(path, "w");
    if (!f) return false;
    char sh[128], eh[128], bh[128], th[64];
    format_uint256_hex(start, sh, sizeof(sh));
    format_uint256_hex(end, eh, sizeof(eh));
    format_uint256_hex(base_key, bh, sizeof(bh));
    format_address_hex(target, th, sizeof(th));
    std::fprintf(f, "version=1\nmode=%s\nstart=%s\nend=%s\ntarget=%s\nbase_key=%s\ntotal_keys=%llu\n",
        mode == SearchMode::Sequential ? "sequential" : "random",
        sh, eh, th, bh, (unsigned long long)total_keys);
    std::fclose(f);
    return true;
}

static bool load_checkpoint(const char* path, SearchMode* mode_out,
    _uint256* start_out, _uint256* end_out, Address* target_out,
    _uint256* base_key_out, uint64_t* total_keys_out) {
    FILE* f = std::fopen(path, "r");
    if (!f) return false;
    char line[512];
    char mode_s[32] = "sequential";
    char start_s[128] = {0}, end_s[128] = {0}, target_s[64] = {0}, base_s[128] = {0};
    uint64_t total = 0;
    while (std::fgets(line, sizeof(line), f)) {
        if (std::strncmp(line, "mode=", 5) == 0) std::snprintf(mode_s, sizeof(mode_s), "%s", line + 5);
        else if (std::strncmp(line, "start=", 6) == 0) std::snprintf(start_s, sizeof(start_s), "%s", line + 6);
        else if (std::strncmp(line, "end=", 4) == 0) std::snprintf(end_s, sizeof(end_s), "%s", line + 4);
        else if (std::strncmp(line, "target=", 7) == 0) std::snprintf(target_s, sizeof(target_s), "%s", line + 7);
        else if (std::strncmp(line, "base_key=", 9) == 0) std::snprintf(base_s, sizeof(base_s), "%s", line + 9);
        else if (std::strncmp(line, "total_keys=", 11) == 0) total = std::strtoull(line + 11, nullptr, 10);
    }
    std::fclose(f);
    size_t n = std::strlen(mode_s);
    while (n > 0 && (mode_s[n - 1] == '\n' || mode_s[n - 1] == '\r')) mode_s[--n] = '\0';
    auto trimnl = [](char* s) {
        size_t m = std::strlen(s);
        while (m > 0 && (s[m - 1] == '\n' || s[m - 1] == '\r')) s[--m] = '\0';
    };
    trimnl(start_s); trimnl(end_s); trimnl(target_s); trimnl(base_s);
    if (base_s[0] == '\0') return false;
    if (mode_out) *mode_out = (std::strcmp(mode_s, "random") == 0) ? SearchMode::Random : SearchMode::Sequential;
    if (start_out) *start_out = parse_hex_uint256(start_s);
    if (end_out) *end_out = parse_hex_uint256(end_s);
    if (target_out) *target_out = parse_hash160_hex(target_s);
    if (base_key_out) *base_key_out = parse_hex_uint256(base_s);
    if (total_keys_out) *total_keys_out = total;
    return true;
}

static bool run_self_test() {
    Address g_addr = cpu_calculate_hash160_compressed(G_X, G_Y);
    static const uint8_t known_h160[20] = {
        0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54, 0x94,
        0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6
    };
    Address expected = host_bytes20_to_address(known_h160);
    if (!address_eq(g_addr, expected)) {
        std::fprintf(stderr, "FAIL: hash160(G) — oczekiwano pubkey 1 pipeline\n");
        char got[64], exp[64];
        format_address_hex(g_addr, got, sizeof(got));
        format_address_hex(expected, exp, sizeof(exp));
        std::fprintf(stderr, "  got=%s exp=%s\n", got, exp);
        return false;
    }

    _uint256 start = parse_hex_uint256("40000000000000000");
    CurvePoint p = cpu_point_multiply(G, start);
    Address p_addr = cpu_calculate_hash160_compressed(p.x, p.y);
    Address puzzle_target = parse_hash160_hex("f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8");
    if (address_eq(p_addr, puzzle_target)) {
        std::fprintf(stderr, "WARN: start key matches puzzle (unexpected)\n");
    }

    CurvePoint p2 = cpu_point_add(p, G);
    _uint256 k2 = cpu_add_256(start, _uint256{0, 0, 0, 0, 0, 0, 0, 1});
    Address a2 = cpu_calculate_hash160_compressed(p2.x, p2.y);
    (void)k2;
    (void)a2;
    std::printf("OK: self-test hash160 pipeline\n");
    return true;
}

static int run_bench(double seconds, uint32_t work_scale) {
    CUDA_CHECK(cudaSetDevice(0));
    uint32_t grid_size = 1U << work_scale;
    if (grid_size < 256) grid_size = 256;
    const uint64_t grid_work = (uint64_t)BLOCK_SIZE * (uint64_t)grid_size * (uint64_t)THREAD_WORK;

    Address target = parse_hash160_hex("f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8");
    uint32_t target_words[5] = {target.a, target.b, target.c, target.d, target.e};
    CUDA_CHECK(cudaMemcpyToSymbol(device_target, target_words, sizeof(target_words)));

    CurvePoint* block_offsets = nullptr;
    CurvePoint* offsets = nullptr;
    CurvePoint* thread_offsets_host = nullptr;
    uint64_t* device_memory_host = nullptr;

    CUDA_CHECK(cudaHostAlloc(&device_memory_host,
        (2 + OUTPUT_BUFFER_SIZE * 3) * sizeof(uint64_t), cudaHostAllocDefault));

    uint64_t* output_counter_host = device_memory_host;
    uint64_t* max_score_host = device_memory_host + 1;
    output_counter_host[0] = 0;
    max_score_host[0] = 2;
    CUDA_CHECK(cudaMemcpyToSymbol(device_memory, device_memory_host, 2 * sizeof(uint64_t)));

    CUDA_CHECK(cudaMalloc(&block_offsets, grid_size * sizeof(CurvePoint)));
    CUDA_CHECK(cudaMalloc(&offsets, (uint64_t)grid_size * BLOCK_SIZE * sizeof(CurvePoint)));
    CUDA_CHECK(cudaHostAlloc(&thread_offsets_host, BLOCK_SIZE * sizeof(CurvePoint), cudaHostAllocDefault));

    CurvePoint* addends_host = new CurvePoint[THREAD_WORK - 1];
    CurvePoint p = G;
    for (int i = 0; i < THREAD_WORK - 1; i++) {
        addends_host[i] = p;
        p = cpu_point_add(p, G);
    }
    CUDA_CHECK(cudaMemcpyToSymbol(addends, addends_host, (THREAD_WORK - 1) * sizeof(CurvePoint)));
    delete[] addends_host;

    _uint256 base_key = parse_hex_uint256("40000000000000000");
    _uint256 key_increment = cpu_mul_256_mod_p(
        cpu_mul_256_mod_p(_uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK},
                          _uint256{0, 0, 0, 0, 0, 0, 0, BLOCK_SIZE}),
        _uint256{0, 0, 0, 0, 0, 0, 0, grid_size});

    CurvePoint* block_offsets_host = new CurvePoint[grid_size];
    CurvePoint block_offset = cpu_point_multiply(G, _uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK * BLOCK_SIZE});
    p = G;
    for (uint32_t i = 0; i < grid_size; i++) {
        block_offsets_host[i] = p;
        p = cpu_point_add(p, block_offset);
    }
    CUDA_CHECK(cudaMemcpy(block_offsets, block_offsets_host, grid_size * sizeof(CurvePoint), cudaMemcpyHostToDevice));
    delete[] block_offsets_host;

    uint64_t bench_start = ms_now();
    uint64_t batch_start = bench_start;
    bool first = true;
    double speed_sum = 0.0;
    int speed_n = 0;
    uint64_t total = 0;

    while (true) {
        double elapsed_bench = (ms_now() - bench_start) / 1000.0;
        if (elapsed_bench >= seconds) break;

        if (!first) {
            gpu_puzzle_work<<<grid_size, BLOCK_SIZE>>>(offsets);
            CUDA_CHECK(cudaDeviceSynchronize());
            uint64_t batch_end = ms_now();
            double elapsed = (batch_end - batch_start) / 1000.0;
            if (elapsed > 0.0) {
                speed_sum += (double)grid_work / elapsed / 1e6;
                speed_n++;
            }
            batch_start = batch_end;
            total += grid_work;
            base_key = cpu_add_256(base_key, key_increment);
            output_counter_host[0] = 0;
            CUDA_CHECK(cudaMemcpyToSymbol(device_memory, device_memory_host, sizeof(uint64_t)));
        }

        CurvePoint thread_offset = cpu_point_multiply(G, _uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK});
        p = cpu_point_multiply(G, cpu_add_256(_uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK - 1}, base_key));
        for (int i = 0; i < BLOCK_SIZE; i++) {
            thread_offsets_host[i] = p;
            p = cpu_point_add(p, thread_offset);
        }
        CUDA_CHECK(cudaMemcpyToSymbol(thread_offsets, thread_offsets_host, BLOCK_SIZE * sizeof(CurvePoint)));
        gpu_address_init<<<grid_size / BLOCK_SIZE, BLOCK_SIZE>>>(block_offsets, offsets);
        CUDA_CHECK(cudaDeviceSynchronize());
        first = false;
    }

    double avg = speed_n > 0 ? speed_sum / speed_n : 0.0;
    std::printf("Benchmark MAGIC: work_scale=%u, grid=%u, ~%.0f mln kluczy/s (%.2f mld prob)\n",
        work_scale, grid_size, avg, (double)total / 1e9);

    cudaFreeHost(device_memory_host);
    cudaFreeHost(thread_offsets_host);
    cudaFree(block_offsets);
    cudaFree(offsets);
    return 0;
}

static int run_search(_uint256 start_key, _uint256 end_key, Address target, uint32_t work_scale,
    SearchMode mode, const char* checkpoint_path, bool resume) {
    CUDA_CHECK(cudaSetDevice(0));

    uint64_t total_keys = 0;
    _uint256 range_start = start_key;
    _uint256 resume_base{};
    bool have_resume_base = false;
    if (resume) {
        SearchMode saved_mode = SearchMode::Sequential;
        _uint256 ck_start{}, ck_end{}, ck_base{};
        Address ck_target{};
        if (!load_checkpoint(checkpoint_path, &saved_mode, &ck_start, &ck_end, &ck_target, &ck_base, &total_keys)) {
            std::fprintf(stderr, "BLAD: brak checkpointu '%s'\n", checkpoint_path);
            return 1;
        }
        range_start = ck_start;
        start_key = ck_start;
        end_key = ck_end;
        target = ck_target;
        resume_base = ck_base;
        have_resume_base = true;
        mode = SearchMode::Sequential;
        char bk[128], rs[128], re[128];
        format_uint256_hex(ck_base, bk, sizeof(bk));
        format_uint256_hex(range_start, rs, sizeof(rs));
        format_uint256_hex(end_key, re, sizeof(re));
        std::fprintf(stderr, "Resume: od base_key=%s, zakres %s..%s, lacznie=%llu kluczy\n",
            bk, rs, re, (unsigned long long)total_keys);
    }

    uint32_t target_words[5] = {target.a, target.b, target.c, target.d, target.e};
    CUDA_CHECK(cudaMemcpyToSymbol(device_target, target_words, sizeof(target_words)));

    uint32_t grid_size = 1U << work_scale;
    if (grid_size < 256) grid_size = 256;
    const uint64_t grid_work = (uint64_t)BLOCK_SIZE * (uint64_t)grid_size * (uint64_t)THREAD_WORK;

    CurvePoint* block_offsets = nullptr;
    CurvePoint* thread_offsets_host = nullptr;
    uint64_t* device_memory_host = nullptr;

    CUDA_CHECK(cudaHostAlloc(&device_memory_host,
        (2 + OUTPUT_BUFFER_SIZE * 3) * sizeof(uint64_t), cudaHostAllocDefault));

    uint64_t* output_counter_host = device_memory_host;
    uint64_t* max_score_host = device_memory_host + 1;
    uint64_t* output_buffer_host = max_score_host + 1;
    uint64_t* output_buffer2_host = output_buffer_host + OUTPUT_BUFFER_SIZE;

    output_counter_host[0] = 0;
    max_score_host[0] = 1;
    CUDA_CHECK(cudaMemcpyToSymbol(device_memory, device_memory_host, 2 * sizeof(uint64_t)));

    CUDA_CHECK(cudaMalloc(&block_offsets, grid_size * sizeof(CurvePoint)));
    CurvePoint* offsets[2] = {nullptr, nullptr};
    CUDA_CHECK(cudaMalloc(&offsets[0], (uint64_t)grid_size * BLOCK_SIZE * sizeof(CurvePoint)));
    CUDA_CHECK(cudaMalloc(&offsets[1], (uint64_t)grid_size * BLOCK_SIZE * sizeof(CurvePoint)));
    CUDA_CHECK(cudaHostAlloc(&thread_offsets_host, BLOCK_SIZE * sizeof(CurvePoint), cudaHostAllocDefault));

    _uint256 key_increment = cpu_mul_256_mod_p(
        cpu_mul_256_mod_p(_uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK},
                          _uint256{0, 0, 0, 0, 0, 0, 0, BLOCK_SIZE}),
        _uint256{0, 0, 0, 0, 0, 0, 0, grid_size});

    CurvePoint* addends_host = new CurvePoint[THREAD_WORK - 1];
    CurvePoint p = G;
    for (int i = 0; i < THREAD_WORK - 1; i++) {
        addends_host[i] = p;
        p = cpu_point_add(p, G);
    }
    CUDA_CHECK(cudaMemcpyToSymbol(addends, addends_host, (THREAD_WORK - 1) * sizeof(CurvePoint)));
    delete[] addends_host;

    CurvePoint* block_offsets_host = new CurvePoint[grid_size];
    CurvePoint block_offset = cpu_point_multiply(G, _uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK * BLOCK_SIZE});
    p = G;
    std::fprintf(stderr, "MAGIC: work_scale=%u, ping-pong buffers, init (%u)...\n", work_scale, grid_size);
    for (uint32_t i = 0; i < grid_size; i++) {
        block_offsets_host[i] = p;
        p = cpu_point_add(p, block_offset);
    }
    CUDA_CHECK(cudaMemcpy(block_offsets, block_offsets_host, grid_size * sizeof(CurvePoint), cudaMemcpyHostToDevice));
    delete[] block_offsets_host;

    _uint256 base_key;
    if (have_resume_base) {
        base_key = resume_base;
    } else if (mode == SearchMode::Random) {
        base_key = random_base_in_range(range_start, end_key, key_increment);
    } else {
        base_key = start_key;
    }
    _uint256 prev_base_key = base_key;
    _uint256 work_base_key = base_key;
    int cur = 0;
    bool have_work = false;
    uint64_t batch_start = ms_now();
    int ret = 0;

    cudaStream_t stream_work, stream_init;
    CUDA_CHECK(cudaStreamCreate(&stream_work));
    CUDA_CHECK(cudaStreamCreate(&stream_init));

    char target_hex[64], rs[128], re[128];
    format_address_hex(target, target_hex, sizeof(target_hex));
    format_uint256_hex(range_start, rs, sizeof(rs));
    format_uint256_hex(end_key, re, sizeof(re));
    std::fprintf(stderr, "MAGIC: tryb=%s | %s..%s | target %s\n",
        mode == SearchMode::Random ? "losowy" : "sekwencyjny", rs, re, target_hex);
    if (mode == SearchMode::Sequential && !resume)
        std::fprintf(stderr, "MAGIC: checkpoint %s | specialized kernel + dual buffer\n", checkpoint_path);

    auto fill_thread_offsets = [&](_uint256 bk) {
        CurvePoint thread_offset = cpu_point_multiply(G, _uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK});
        CurvePoint pp = cpu_point_multiply(G, cpu_add_256(_uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK - 1}, bk));
        for (int i = 0; i < BLOCK_SIZE; i++) {
            thread_offsets_host[i] = pp;
            pp = cpu_point_add(pp, thread_offset);
        }
    };

    /* pierwszy init */
    fill_thread_offsets(base_key);
    CUDA_CHECK(cudaMemcpyToSymbol(thread_offsets, thread_offsets_host, BLOCK_SIZE * sizeof(CurvePoint)));
    gpu_address_init<<<grid_size / BLOCK_SIZE, BLOCK_SIZE, 0, stream_init>>>(block_offsets, offsets[cur]);
    CUDA_CHECK(cudaStreamSynchronize(stream_init));
    work_base_key = base_key;
    have_work = true;

    while (have_work) {
        gpu_puzzle_work<<<grid_size, BLOCK_SIZE, 0, stream_work>>>(offsets[cur]);

        /* nastepny klucz + init do drugiego bufora ROWNIEGLE z work */
        bool scheduled_next = false;
        _uint256 next_key = base_key;
        if (mode == SearchMode::Random) {
            next_key = random_base_in_range(range_start, end_key, key_increment);
            scheduled_next = true;
        } else {
            next_key = cpu_add_256(base_key, key_increment);
            if (!gt_256(next_key, end_key)) scheduled_next = true;
        }

        if (scheduled_next) {
            fill_thread_offsets(next_key);
            CUDA_CHECK(cudaMemcpyToSymbolAsync(thread_offsets, thread_offsets_host,
                BLOCK_SIZE * sizeof(CurvePoint), 0, cudaMemcpyHostToDevice, stream_init));
            gpu_address_init<<<grid_size / BLOCK_SIZE, BLOCK_SIZE, 0, stream_init>>>(
                block_offsets, offsets[1 - cur]);
        }

        CUDA_CHECK(cudaStreamSynchronize(stream_work));
        CUDA_CHECK(cudaMemcpyFromSymbolAsync(device_memory_host, device_memory,
            (2 + OUTPUT_BUFFER_SIZE * 3) * sizeof(uint64_t), 0, cudaMemcpyDeviceToHost, stream_init));
        CUDA_CHECK(cudaStreamSynchronize(stream_init));

        uint64_t batch_end = ms_now();
        double elapsed = (batch_end - batch_start) / 1000.0;
        total_keys += grid_work;
        if (elapsed > 0.0) {
            double speed = (double)grid_work / elapsed / 1e6;
            std::fprintf(stderr, "MAGIC: %.0f mln | ~%.0f M/s | lacznie %.2f mld    \r",
                (double)grid_work / 1e6, speed, (double)total_keys / 1e9);
        }
        batch_start = batch_end;

        prev_base_key = work_base_key;
        if (output_counter_host[0] > 0) {
            uint32_t nout = (uint32_t)output_counter_host[0];
            if (nout > OUTPUT_BUFFER_SIZE) nout = OUTPUT_BUFFER_SIZE;
            for (uint32_t i = 0; i < nout; i++) {
                if (output_buffer2_host[i] <= 0) continue;
                uint64_t k_offset = output_buffer_host[i];
                _uint256 k = cpu_add_256(prev_base_key,
                    cpu_add_256(_uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK},
                        _uint256{0, 0, 0, 0, 0, 0,
                            (uint32_t)(k_offset >> 32), (uint32_t)(k_offset & 0xFFFFFFFF)}));
                CurvePoint cp = cpu_point_multiply(G, k);
                Address addr = cpu_calculate_hash160_compressed(cp.x, cp.y);
                if (!address_eq(addr, target)) continue;
                char pk[128], ah[64];
                format_uint256_hex(k, pk, sizeof(pk));
                format_address_hex(addr, ah, sizeof(ah));
                std::printf("\n*** ZNALEZIONO ***\nAdres: 1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU\nKlucz: %s\nHash160: %s\n", pk, ah);
                std::fflush(stdout);
                FILE* ff = std::fopen("FOUND.txt", "w");
                if (ff) {
                    std::fprintf(ff, "*** ZNALEZIONO ***\nAdres: 1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU\nKlucz: %s\nHash160: %s\n", pk, ah);
                    std::fclose(ff);
                }
                FILE* lf = std::fopen("logs/FOUND.txt", "w");
                if (lf) {
                    std::fprintf(lf, "*** ZNALEZIONO ***\nAdres: 1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU\nKlucz: %s\nHash160: %s\n", pk, ah);
                    std::fclose(lf);
                }
                ret = 0;
                goto cleanup;
            }
        }

        output_counter_host[0] = 0;
        CUDA_CHECK(cudaMemcpyToSymbolAsync(device_memory, device_memory_host, sizeof(uint64_t),
            0, cudaMemcpyHostToDevice, stream_init));
        CUDA_CHECK(cudaStreamSynchronize(stream_init));

        if (!scheduled_next) break;

        /* random tez zapisuje — HTML / Telegram widza total_keys */
        if (!save_checkpoint(checkpoint_path, mode, range_start, end_key, target, next_key, total_keys))
            std::fprintf(stderr, "\nWARN: checkpoint %s\n", checkpoint_path);

        base_key = next_key;
        work_base_key = next_key;
        cur = 1 - cur;
        have_work = true;
    }

cleanup:
    cudaStreamDestroy(stream_work);
    cudaStreamDestroy(stream_init);
    cudaFreeHost(device_memory_host);
    cudaFreeHost(thread_offsets_host);
    cudaFree(block_offsets);
    cudaFree(offsets[0]);
    cudaFree(offsets[1]);
    return ret;
}

static int run_magic_auto() {
    std::printf("\n*** MAGIC AUTO-TUNE ***\nSzukam najlepszego work-scale na Twojej karcie...\n\n");
    uint32_t best_scale = 16;
    double best_speed = 0.0;
    for (uint32_t s = 14; s <= 18; s++) {
        std::printf("--- work_scale=%u ---\n", s);
        /* krotki bench; run_bench drukuje wynik — zlap z ponownego wewnetrznego */
        CUDA_CHECK(cudaSetDevice(0));
        /* uzyj run_bench i porownaj przez stderr timing — prościej: osobna funkcja */
        uint32_t grid_size = 1U << s;
        if (grid_size < 256) grid_size = 256;
        const uint64_t grid_work = (uint64_t)BLOCK_SIZE * (uint64_t)grid_size * (uint64_t)THREAD_WORK;

        Address target = parse_hash160_hex("f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8");
        uint32_t tw[5] = {target.a, target.b, target.c, target.d, target.e};
        CUDA_CHECK(cudaMemcpyToSymbol(device_target, tw, sizeof(tw)));

        CurvePoint* block_offsets = nullptr;
        CurvePoint* offsets = nullptr;
        CurvePoint* thread_offsets_host = nullptr;
        uint64_t* device_memory_host = nullptr;
        CUDA_CHECK(cudaHostAlloc(&device_memory_host, (2 + OUTPUT_BUFFER_SIZE * 3) * sizeof(uint64_t), cudaHostAllocDefault));
        device_memory_host[0] = 0;
        device_memory_host[1] = 1;
        CUDA_CHECK(cudaMemcpyToSymbol(device_memory, device_memory_host, 2 * sizeof(uint64_t)));
        CUDA_CHECK(cudaMalloc(&block_offsets, grid_size * sizeof(CurvePoint)));
        CUDA_CHECK(cudaMalloc(&offsets, (uint64_t)grid_size * BLOCK_SIZE * sizeof(CurvePoint)));
        CUDA_CHECK(cudaHostAlloc(&thread_offsets_host, BLOCK_SIZE * sizeof(CurvePoint), cudaHostAllocDefault));

        CurvePoint* addends_host = new CurvePoint[THREAD_WORK - 1];
        CurvePoint p = G;
        for (int i = 0; i < THREAD_WORK - 1; i++) {
            addends_host[i] = p;
            p = cpu_point_add(p, G);
        }
        CUDA_CHECK(cudaMemcpyToSymbol(addends, addends_host, (THREAD_WORK - 1) * sizeof(CurvePoint)));
        delete[] addends_host;

        _uint256 base_key = parse_hex_uint256("40000000000000000");
        _uint256 key_increment = cpu_mul_256_mod_p(
            cpu_mul_256_mod_p(_uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK},
                              _uint256{0, 0, 0, 0, 0, 0, 0, BLOCK_SIZE}),
            _uint256{0, 0, 0, 0, 0, 0, 0, grid_size});
        CurvePoint* block_offsets_host = new CurvePoint[grid_size];
        CurvePoint block_offset = cpu_point_multiply(G, _uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK * BLOCK_SIZE});
        p = G;
        for (uint32_t i = 0; i < grid_size; i++) {
            block_offsets_host[i] = p;
            p = cpu_point_add(p, block_offset);
        }
        CUDA_CHECK(cudaMemcpy(block_offsets, block_offsets_host, grid_size * sizeof(CurvePoint), cudaMemcpyHostToDevice));
        delete[] block_offsets_host;

        CurvePoint thread_offset = cpu_point_multiply(G, _uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK});
        p = cpu_point_multiply(G, cpu_add_256(_uint256{0, 0, 0, 0, 0, 0, 0, THREAD_WORK - 1}, base_key));
        for (int i = 0; i < BLOCK_SIZE; i++) {
            thread_offsets_host[i] = p;
            p = cpu_point_add(p, thread_offset);
        }
        CUDA_CHECK(cudaMemcpyToSymbol(thread_offsets, thread_offsets_host, BLOCK_SIZE * sizeof(CurvePoint)));
        gpu_address_init<<<grid_size / BLOCK_SIZE, BLOCK_SIZE>>>(block_offsets, offsets);
        CUDA_CHECK(cudaDeviceSynchronize());

        /* warm-up */
        gpu_puzzle_work<<<grid_size, BLOCK_SIZE>>>(offsets);
        CUDA_CHECK(cudaDeviceSynchronize());

        uint64_t t0 = ms_now();
        int batches = 0;
        while (ms_now() - t0 < 2500) {
            gpu_puzzle_work<<<grid_size, BLOCK_SIZE>>>(offsets);
            CUDA_CHECK(cudaDeviceSynchronize());
            base_key = cpu_add_256(base_key, key_increment);
            batches++;
        }
        uint64_t t1 = ms_now();
        double sec = (t1 - t0) / 1000.0;
        double mps = sec > 0 ? (double)batches * (double)grid_work / sec / 1e6 : 0.0;
        std::printf("  scale %u -> ~%.0f M/s (%d batchy)\n", s, mps, batches);
        if (mps > best_speed) {
            best_speed = mps;
            best_scale = s;
        }

        cudaFreeHost(device_memory_host);
        cudaFreeHost(thread_offsets_host);
        cudaFree(block_offsets);
        cudaFree(offsets);
    }
    std::printf("\n*** MAGIC: najlepszy work_scale=%u (~%.0f M/s) ***\n", best_scale, best_speed);
    std::printf("Uruchom: bin\\puzzle71-cuda.exe --work-scale %u\n", best_scale);
    std::printf("Albo:    set PUZZLE71_WORK_SCALE=%u\n\n", best_scale);
    return 0;
}

static void print_usage() {
    std::printf(
        "puzzle71-cuda MAGIC — GPU Puzzle #71 (fused hash + dual buffer + special kernel)\n\n"
        "Uzycie:\n"
        "  puzzle71-cuda --test\n"
        "  puzzle71-cuda --bench [sekundy]\n"
        "  puzzle71-cuda --magic          auto-dobor work-scale (POLECAM)\n"
        "  puzzle71-cuda [opcje]\n\n"
        "Tryby szukania:\n"
        "  --mode sequential   po kolei od --start (domyslnie), zapisuje checkpoint\n"
        "  --mode random         losowo w zakresie --start .. --end\n"
        "  --resume              kontynuuj sekwencyjnie od ostatniego checkpointu\n\n"
        "Opcje:\n"
        "  --start HEX  --end HEX  --target HASH160_HEX\n"
        "  --checkpoint PLIK     domyslnie: puzzle71.progress\n"
        "  --work-scale N        10-20, domyslnie 16\n\n"
        "Domyslnie Puzzle #71:\n"
        "  start=40000000000000000  end=7ffffffffffffffff\n"
        "  target=f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8\n"
    );
}

int main(int argc, char** argv) {
    int device_count = 0;
    if (cudaGetDeviceCount(&device_count) != cudaSuccess || device_count == 0) {
        std::fprintf(stderr, "Brak urzadzenia CUDA\n");
        return 1;
    }

    cudaDeviceProp prop{};
    cudaGetDeviceProperties(&prop, 0);
    std::printf("GPU: %s (SM %d.%d)\n", prop.name, prop.major, prop.minor);

    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "--test") == 0) {
            if (!run_self_test()) return 1;
            return run_bench(3.0, read_work_scale(argc, argv));
        }
        if (std::strcmp(argv[i], "--bench") == 0) {
            double sec = 10.0;
            if (i + 1 < argc && argv[i + 1][0] != '-') sec = std::atof(argv[i + 1]);
            return run_bench(sec, read_work_scale(argc, argv));
        }
        if (std::strcmp(argv[i], "--magic") == 0 || std::strcmp(argv[i], "--auto") == 0) {
            if (!run_self_test()) return 1;
            return run_magic_auto();
        }
        if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0) {
            print_usage();
            return 0;
        }
    }

    const char* start_hex = "40000000000000000";
    const char* end_hex = "7ffffffffffffffff";
    const char* target_hex = "f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8";
    const char* checkpoint_path = DEFAULT_CHECKPOINT;
    SearchMode mode = SearchMode::Sequential;
    bool resume = false;

    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "--start") == 0 && i + 1 < argc) start_hex = argv[++i];
        else if (std::strcmp(argv[i], "--end") == 0 && i + 1 < argc) end_hex = argv[++i];
        else if (std::strcmp(argv[i], "--target") == 0 && i + 1 < argc) target_hex = argv[++i];
        else if (std::strcmp(argv[i], "--checkpoint") == 0 && i + 1 < argc) checkpoint_path = argv[++i];
        else if (std::strcmp(argv[i], "--resume") == 0) resume = true;
        else if (std::strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            const char* m = argv[++i];
            if (std::strcmp(m, "random") == 0) mode = SearchMode::Random;
            else if (std::strcmp(m, "sequential") == 0) mode = SearchMode::Sequential;
            else std::fprintf(stderr, "Nieznany tryb '%s' — uzywam sequential\n", m);
        }
    }

    if (resume && mode == SearchMode::Random) {
        std::fprintf(stderr, "UWAGA: --resume wymusza tryb sequential\n");
        mode = SearchMode::Sequential;
    }

    if (!run_self_test()) return 1;

    _uint256 start = parse_hex_uint256(start_hex);
    _uint256 end = parse_hex_uint256(end_hex);
    Address target = parse_hash160_hex(target_hex);

    return run_search(start, end, target, read_work_scale(argc, argv),
        mode, checkpoint_path, resume);
}
