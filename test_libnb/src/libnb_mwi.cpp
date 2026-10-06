/*
 * Copyright (C) 2015-2017 The Android-x86 Open Source Project
 * Original NativeBridge forwarding implementation by Chih-Wei Huang
 * <cwhuang@linux.org.tw>; licensed under the GNU GPL, version 2 or later.
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * MWI test_libnb build for Houdini 11_38765 / Android 11.
 *
 * Based on qwerty12356-wart/test_libnb, commit:
 * 4f89b1f622d83082bc644fc216a9d6c70d7df8f7
 * BSD-2-Clause portions Copyright (c) 2024, qwerty12356-wart.
 *
 * MWI change:
 * - Preserve upstream Blue Archive behavior:
 *     Patch_Performance_pkey_mprotect
 * - Add Mirishita-specific behavior:
 *     Patch_Performance_pkey_mprotect + Patch_exp_01
 *
 * The NativeBridge forwarding code derives from Android-x86/AOSP interfaces,
 * following the upstream test_libnb implementation.
 */

extern "C" {
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
typedef long intptr_t;
typedef unsigned long size_t;

void *memcpy(void *, const void *, size_t);
const char *strstr(const char *, const char *);
int strcmp(const char *, const char *);
char *strchr(const char *, int);
void *dlopen(const char *, int);
void *dlsym(void *, const char *);
int dlclose(void *);
char *dlerror(void);
int mprotect(void *, size_t, int);
int __android_log_print(int, const char *, const char *, ...);

struct Dl_info { const char *dli_fname; void *dli_fbase; const char *dli_sname; void *dli_saddr; };
int dladdr(const void *, Dl_info *);
}

#define RTLD_LAZY 1
#define PROT_READ  0x1
#define PROT_WRITE 0x2
#define PROT_EXEC  0x4
#define ANDROID_LOG_DEBUG 3
#define ANDROID_LOG_INFO  4
#define ANDROID_LOG_ERROR 6

#ifdef LOG_DEBUG
#define debug_print(...) __android_log_print(ANDROID_LOG_DEBUG, "libnb_custom", __VA_ARGS__)
#else
#define debug_print(...)
#endif
#define error_print(...) __android_log_print(ANDROID_LOG_ERROR, "libnb_custom", __VA_ARGS__)
#define info_print(...)  __android_log_print(ANDROID_LOG_INFO,  "libnb_custom", __VA_ARGS__)

namespace android {
struct NativeBridgeRuntimeCallbacks;
struct NativeBridgeRuntimeValues;
struct native_bridge_namespace_t;
struct fake_siginfo;
typedef bool (*NativeBridgeSignalHandlerFn)(int, fake_siginfo*, void*);
enum JNICallType { kJNICallTypeRegular = 1, kJNICallTypeCriticalNative = 2 };

struct NativeBridgeCallbacks {
    uint32_t version;
    bool (*initialize)(const NativeBridgeRuntimeCallbacks*, const char*, const char*);
    void* (*loadLibrary)(const char*, int);
    void* (*getTrampoline)(void*, const char*, const char*, uint32_t);
    bool (*isSupported)(const char*);
    const NativeBridgeRuntimeValues* (*getAppEnv)(const char*);
    bool (*isCompatibleWith)(uint32_t);
    NativeBridgeSignalHandlerFn (*getSignalHandler)(int);
    int (*unloadLibrary)(void*);
    const char* (*getError)();
    bool (*isPathSupported)(const char*);
    bool (*initAnonymousNamespace)(const char*, const char*);
    native_bridge_namespace_t* (*createNamespace)(const char*, const char*, const char*, uint64_t, const char*, native_bridge_namespace_t*);
    bool (*linkNamespaces)(native_bridge_namespace_t*, native_bridge_namespace_t*, const char*);
    void* (*loadLibraryExt)(const char*, int, native_bridge_namespace_t*);
    native_bridge_namespace_t* (*getVendorNamespace)();
    native_bridge_namespace_t* (*getExportedNamespace)(const char*);
    void (*preZygoteFork)();
    void* (*getTrampolineWithJNICallType)(void*, const char*, const char*, uint32_t, JNICallType);
    void* (*getTrampolineForFunctionPointer)(const void*, const char*, uint32_t, JNICallType);
};
}

#if __SIZEOF_POINTER__ == 4
#define IS_32 1
#else
#define IS_64 1
#endif

static inline int PatchHex_8(void* baseaddress, int offset, uint8_t original_hex, uint8_t new_hex) {
    uint8_t* p = (uint8_t*)baseaddress + offset;
    uint8_t v = 0;
    memcpy(&v, p, 1);
    if (v == original_hex) { memcpy(p, &new_hex, 1); return 0; }
    if (v == new_hex) return 0;
    return 1;
}
static inline int PatchHex_16(void* baseaddress, int offset, uint16_t original_hex, uint16_t new_hex) {
    uint8_t* p = (uint8_t*)baseaddress + offset;
    uint16_t v = 0;
    memcpy(&v, p, 2);
    if (v == original_hex) { memcpy(p, &new_hex, 2); return 0; }
    if (v == new_hex) return 0;
    return 1;
}
static inline int PatchHex_32(void* baseaddress, int offset, uint32_t original_hex, uint32_t new_hex) {
    uint8_t* p = (uint8_t*)baseaddress + offset;
    uint32_t v = 0;
    memcpy(&v, p, 4);
    if (v == original_hex) { memcpy(p, &new_hex, 4); return 0; }
    if (v == new_hex) return 0;
    return 1;
}

#ifdef IS_32
static unsigned int sizeofNB = 5u * 1024u * 1024u;
#else
static unsigned int sizeofNB = 6u * 1024u * 1024u;
#endif

static void Patch_Permissive_pkey_mprotect(void* nbbase) {
    int res = 0;
#ifndef IS_32
    res |= PatchHex_8(nbbase, 0x3099D8, 0xFB, 0xFF);
#endif
    if (res) error_print("Patch_Permissive_pkey_Mprotect Failed.");
}

static void Patch_Permissive_mmap(void* nbbase) {
    int res = 0;
#ifndef IS_32
    res |= PatchHex_32(nbbase, 0x3062A5, 0xFFFBB848u, 0xFFFFB848u);
#endif
    if (res) error_print("Patch_Permissive_mmap Failed.");
}

static void Patch_Performance_pkey_mprotect(void* nbbase) {
    int res = 0;
#ifndef IS_32
    res |= PatchHex_32(nbbase, 0x309B42, 0xEE2F89E8u, 0x90909090u);
    res |= PatchHex_8(nbbase, 0x309B46, 0xFF, 0x90);
#endif
    if (res) error_print("Patch_Performance_pkey_mprotect Failed.");
}

static void Patch_exp_01(void* nbbase) {
    int res = 0;
#ifndef IS_32
    res |= PatchHex_16(nbbase, 0x2F7877, 0x940F, 0x01B1);
    res |= PatchHex_8(nbbase, 0x2F7879, 0xC1, 0x90);
#endif
    if (res) error_print("Patch_exp_01 failed.");
}

// MWI intentionally keeps only the app-specific patch paths needed here.
// Other upstream game-specific hooks (Roblox/Supercell) are not enabled in this build.

static void Patch_NB(void* nbbase, const android::NativeBridgeRuntimeCallbacks*, const char* app_code_cache_dir, const char*) {
    Patch_Permissive_pkey_mprotect(nbbase);
    Patch_Permissive_mmap(nbbase);
    if (!app_code_cache_dir) return;

    // Upstream test_libnb behavior.
    if (strstr(app_code_cache_dir, "com.nexon.bluearchive")) {
        Patch_Performance_pkey_mprotect(nbbase);
    }

    // MWI addition based on the documented Mirishita-compatible approach.
    if (strstr(app_code_cache_dir, "com.bandainamcoent.imas_millionlive_theaterdays")) {
        Patch_Performance_pkey_mprotect(nbbase);
        Patch_exp_01(nbbase);
    }

}

static inline void initPatches(void* nbbase, const android::NativeBridgeRuntimeCallbacks* cbs, const char* dir, const char* isa) {
    mprotect(nbbase, sizeofNB, PROT_EXEC | PROT_READ | PROT_WRITE);
    Patch_NB(nbbase, cbs, dir, isa);
    mprotect(nbbase, sizeofNB, PROT_EXEC | PROT_READ);
}

namespace android {
static void* native_handle = 0;
static NativeBridgeCallbacks* callbacks = 0;

static bool is_native_bridge_enabled() { return true; }

static NativeBridgeCallbacks* get_callbacks() {
    if (!callbacks) {
        const char* libnb =
#ifdef IS_32
            "/system/lib/libhoudini.so";
#else
            "/system/lib64/libhoudini.so";
#endif
        if (!native_handle) {
            native_handle = dlopen(libnb, RTLD_LAZY);
            if (!native_handle) {
                error_print("Failed to open %s: %s", libnb, dlerror());
                return 0;
            }
        }
        callbacks = (NativeBridgeCallbacks*)dlsym(native_handle, "NativeBridgeItf");
    }
    return callbacks;
}

static bool native_bridge2_initialize(const NativeBridgeRuntimeCallbacks* art_cbs, const char* app_code_cache_dir, const char* isa) {
    if (!is_native_bridge_enabled()) return false;
    NativeBridgeCallbacks* nbcb = get_callbacks();
    if (!nbcb) return false;
    Dl_info dlinf = {};
    if (dladdr(nbcb, &dlinf) && dlinf.dli_fbase) initPatches(dlinf.dli_fbase, art_cbs, app_code_cache_dir, isa);
    return nbcb->initialize(art_cbs, app_code_cache_dir, isa);
}
static void* native_bridge2_loadLibrary(const char* p, int f) { auto* cb=get_callbacks(); return cb?cb->loadLibrary(p,f):0; }
static void* native_bridge2_getTrampoline(void* h,const char*n,const char*s,uint32_t l){auto*cb=get_callbacks();return cb?cb->getTrampoline(h,n,s,l):0;}
static bool native_bridge2_isSupported(const char*p){auto*cb=get_callbacks();return cb?cb->isSupported(p):false;}
static const NativeBridgeRuntimeValues* native_bridge2_getAppEnv(const char*a){auto*cb=get_callbacks();return cb?cb->getAppEnv(a):0;}
static bool native_bridge2_isCompatibleWith(uint32_t v){auto*cb=get_callbacks();return cb?cb->isCompatibleWith(v):(v<=3);}
static NativeBridgeSignalHandlerFn native_bridge2_getSignalHandler(int s){auto*cb=get_callbacks();return cb?cb->getSignalHandler(s):0;}
static int native_bridge3_unloadLibrary(void*h){auto*cb=get_callbacks();return cb?cb->unloadLibrary(h):-1;}
static const char* native_bridge3_getError(){auto*cb=get_callbacks();return cb?cb->getError():"unknown";}
static bool native_bridge3_isPathSupported(const char*p){auto*cb=get_callbacks();return cb&&cb->isPathSupported(p);}
static bool native_bridge3_initAnonymousNamespace(const char*a,const char*b){auto*cb=get_callbacks();return cb&&cb->initAnonymousNamespace(a,b);}
static native_bridge_namespace_t* native_bridge3_createNamespace(const char*a,const char*b,const char*c,uint64_t d,const char*e,native_bridge_namespace_t*f){auto*cb=get_callbacks();return cb?cb->createNamespace(a,b,c,d,e,f):0;}
static bool native_bridge3_linkNamespaces(native_bridge_namespace_t*a,native_bridge_namespace_t*b,const char*c){auto*cb=get_callbacks();return cb&&cb->linkNamespaces(a,b,c);}
static void* native_bridge3_loadLibraryExt(const char*a,int b,native_bridge_namespace_t*c){auto*cb=get_callbacks();return cb?cb->loadLibraryExt(a,b,c):0;}
static native_bridge_namespace_t* native_bridge4_getVendorNamespace(){auto*cb=get_callbacks();return cb?cb->getVendorNamespace():0;}
static native_bridge_namespace_t* native_bridge5_getExportedNamespace(const char*n){auto*cb=get_callbacks();return cb?cb->getExportedNamespace(n):0;}
static void native_bridge6_preZygoteFork(){auto*cb=get_callbacks();if(cb&&cb->preZygoteFork)cb->preZygoteFork();}
static void* native_bridge6_getTrampolineWithJNICallType(void*h,const char*n,const char*s,uint32_t l,JNICallType t){auto*cb=get_callbacks();return cb&&cb->getTrampolineWithJNICallType?cb->getTrampolineWithJNICallType(h,n,s,l,t):0;}
static void* native_bridge6_getTrampolineForFunctionPointer(const void*m,const char*s,uint32_t l,JNICallType t){auto*cb=get_callbacks();return cb&&cb->getTrampolineForFunctionPointer?cb->getTrampolineForFunctionPointer(m,s,l,t):0;}

__attribute__((destructor)) static void on_dlclose(){ if(native_handle){ dlclose(native_handle); native_handle=0; callbacks=0; } }

extern "C" __attribute__((visibility("default"))) NativeBridgeCallbacks NativeBridgeItf = {
    5,
    native_bridge2_initialize,
    native_bridge2_loadLibrary,
    native_bridge2_getTrampoline,
    native_bridge2_isSupported,
    native_bridge2_getAppEnv,
    native_bridge2_isCompatibleWith,
    native_bridge2_getSignalHandler,
    native_bridge3_unloadLibrary,
    native_bridge3_getError,
    native_bridge3_isPathSupported,
    native_bridge3_initAnonymousNamespace,
    native_bridge3_createNamespace,
    native_bridge3_linkNamespaces,
    native_bridge3_loadLibraryExt,
    native_bridge4_getVendorNamespace,
    native_bridge5_getExportedNamespace,
    native_bridge6_preZygoteFork,
    native_bridge6_getTrampolineWithJNICallType,
    native_bridge6_getTrampolineForFunctionPointer
};
}

// Make the ELF self-identify as Android API 30, like an NDK-built library.
struct AndroidIdentNote { uint32_t namesz, descsz, type; char name[8]; uint32_t api; };
__attribute__((section(".note.android.ident"), used, aligned(4)))
static const AndroidIdentNote kAndroidIdent = {8, 4, 1, {'A','n','d','r','o','i','d','\0'}, 30};
