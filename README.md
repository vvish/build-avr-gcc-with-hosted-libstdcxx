# Build gcc-avr with libstdc++

The project contains helper script and patches for libstdc++ and avr-libc
to build hosted and freestanding versions of the c++ standard library.

According to standard the c++ standard library can be build in two variants:
   - hosted;
   - freestanding.

## Freestanding

The 'freestanding' library is supposed to be used on the platforms without
operating system. The standard requires only limited subset of the library
headers to be available in this mode. Unfortunately, even such facilities,
crucial for some the language features, like std::move and std::forward (from
the <utility> header) are excluded from the 'freestanding' variant.
To avoid necessity of porting of the missing components 'hosted' libstdc++
can be built.

## Hosted

The hosted variant contains all standard library components and is dependant on
the operating system support. In practice that means that standard C library
for the target should satisfy compilation dependencies of the libstdc++
components included in the hosted build. The libstdc++ build system detects if
some dependencies are missing and in some cases defines non-functional stubs as
a replacement (for instance in the <filesystem> components build).

### Hosted libstdc++ for the avr target

Some changes for the libstdc++ and avr-libc are required to enable hosted
build. The patches can be found in the patch folder. The patches are part of
the upstream and will be available starting from the gcc 11 release. They can
be backported into gcc 9 and 10.

## Support for the <stdio.h> based iostreams

The patch adds support for pure stdio-based iostreams (without dependencies
on <unistd.h>). It is not required for hosted build of the libstdc++ but
enables iostreams to be used with avr-libc stdio abstraction.

## Script

The script facilitates the build process. It retrieves the specified version of
the gcc, applies the patches if needed and performs the build itself. Either
past stable versions (starting from 9) or trunk can be chosen as a target gcc
version. If the stable version doesn't contain required patches they will be
applied by the script.

```console
$ bash ./build-avr-gcc.bash --help

build-avr-gcc.bash [OPTIONS]

  Script fetches sources and builds gcc and environment
  for the avr target.

  The steps are performed:
  1. Download and build binutils
  2. Download and build gcc for avr
  3. Download avr libc and build it with gcc for avr
  3. Rebuild gcc for avr with enabled hosted libstdc++

  OPTIONS are:
    -g, --gcc             gcc version to build
    -o, --output-dir      directory to place build artifacts (default: ./out)
    -p, --preserve        do not remove intermediate artifacts
    -l, --libstdcxx       no|freestanding|hosted|hosted+streams
                            no - do not build libstdc++
                            freestanding - build freestanding version
                            hosted - build hosted
                            hosted+streams - build hosted +
                              apply patch for streams via stdio
                              if not included

    -h, --help            display this help
```
## License

The patches for the libstdc++ are part of the gcc repository and are the
subject of the corresponding licensing:
https://gcc.gnu.org/onlinedocs/libstdc++/manual/license.html
