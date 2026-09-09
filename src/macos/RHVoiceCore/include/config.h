/* Stand-in for the two config.h files that the SCons and CMake builds generate into the
 * source tree (src/core/config.h and src/include/core/config.h). The macOS build passes
 * every value on the command line instead (see Config/Core.xcconfig); this header only
 * checks that it happened and supplies the defaults the engine expects.
 *
 * If a SCons or CMake run has generated the real files, they shadow this one because
 * quoted includes search the including file's directory first. scripts/build.sh refuses
 * to build in that case. */
#ifndef RHVOICE_MACOS_CONFIG_H
#define RHVOICE_MACOS_CONFIG_H

#ifndef VERSION
#error "VERSION must be defined by the build (Config/Version.xcconfig)."
#endif

#ifndef PACKAGE
#define PACKAGE "RHVoice"
#endif

/* Compile-time data/config locations are unused on macOS: paths are always passed at
 * runtime (app-group container) or through RHVOICE_DATA_PATH / RHVOICE_CONFIG_PATH. */
#ifndef DATA_PATH
#define DATA_PATH ""
#endif
#ifndef CONFIG_PATH
#define CONFIG_PATH ""
#endif

#ifndef ENABLE_SONIC
#define ENABLE_SONIC 0
#endif
#ifndef ENABLE_PKG
#define ENABLE_PKG 0
#endif

#endif /* RHVOICE_MACOS_CONFIG_H */
