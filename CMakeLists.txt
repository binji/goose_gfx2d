# The gfx2d package's native part: the text layer, stb_truetype under the C
# API that text.goose declares its extern fns against (src/text/). The rest
# of the package is Goose, and draws through gfx, which this does not link:
# gfx is a package of its own, which a program using gfx2d already has.
# Built by the Goose compiler through its wrapper project when a program
# needs the package (Goose's docs/packages.md). What a user of the package
# links is goose_gfx2d_package.

cmake_minimum_required(VERSION 3.20)
project(goose_gfx2d_package C)

# stb_truetype.h: vendored under third_party/stb (with its license), or
# another stb tree named in GOOSE_GFX2D_stb. Without the header nothing
# of the package's C would build, and a program using it would fail later
# with undefined gs_gfx2d_* symbols, so the configure fails here instead.
set(GOOSE_GFX2D_stb "" CACHE PATH "A directory holding stb_truetype.h, instead of third_party/stb")
if(NOT GOOSE_GFX2D_stb)
    set(GOOSE_GFX2D_stb "${CMAKE_CURRENT_SOURCE_DIR}/third_party/stb")
endif()
if(NOT EXISTS "${GOOSE_GFX2D_stb}/stb_truetype.h")
    message(FATAL_ERROR "gfx2d: ${GOOSE_GFX2D_stb}/stb_truetype.h is missing. The package's text layer "
                        "needs stb_truetype.h, which the repository carries under third_party/stb; restore "
                        "it, or set GOOSE_GFX2D_stb to a directory that has it.")
endif()

add_library(goose_gfx2d_text STATIC src/text/text_api.h src/text/text_font.c)
target_include_directories(goose_gfx2d_text PRIVATE "${GOOSE_GFX2D_stb}")
set_target_properties(goose_gfx2d_text PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON
                      POSITION_INDEPENDENT_CODE ON)
if(MSVC)
    target_compile_options(goose_gfx2d_text PRIVATE /W4 /utf-8)
    target_compile_definitions(goose_gfx2d_text PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(goose_gfx2d_text PRIVATE -Wall -Wextra -Wno-missing-field-initializers)
    target_link_libraries(goose_gfx2d_text PUBLIC m)
endif()

add_library(goose_gfx2d_package INTERFACE)
target_link_libraries(goose_gfx2d_package INTERFACE goose_gfx2d_text)
