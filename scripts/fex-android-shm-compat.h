#pragma once

#ifdef __ANDROID__

#include <cerrno>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

// Bionic lacks shm_open/shm_unlink. Keep one named memfd owner for FEX UnixLib
// and return a duplicate on each open so mappings can grow safely?
static int fex_android_shm_owner = -1;

static int fex_android_shm_open(const char* name, int flags, mode_t mode) {
  (void)mode;

  if ((flags & O_CREAT) != 0) {
    if (fex_android_shm_owner >= 0) {
      close(fex_android_shm_owner);
    }

    const char* memfd_name = name != nullptr && name[0] == '/' ? name + 1 : name;
    fex_android_shm_owner = memfd_create(memfd_name, MFD_CLOEXEC);
    if (fex_android_shm_owner < 0) {
      return -1;
    }
  }

  if (fex_android_shm_owner < 0) {
    errno = ENOENT;
    return -1;
  }

  if ((flags & O_TRUNC) != 0 && ftruncate(fex_android_shm_owner, 0) != 0) {
    return -1;
  }

  return dup(fex_android_shm_owner);
}

static int fex_android_shm_unlink(const char* name) {
  (void)name;

  if (fex_android_shm_owner < 0) {
    errno = ENOENT;
    return -1;
  }

  const int result = close(fex_android_shm_owner);
  fex_android_shm_owner = -1;
  return result;
}

#define shm_open fex_android_shm_open
#define shm_unlink fex_android_shm_unlink

#endif
