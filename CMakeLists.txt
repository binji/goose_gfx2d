# The gfx2d package's native part: the text layer, stb_truetype under the C
# API that text.goose declares its extern fns against (src/text/). The rest
# of the package is Goose, and draws through gfx, which this does not link:
# gfx is a package of its own, which a program using gfx2d already has.
# Built by the Goose compiler through its wrapper project when a program
# needs the package (Goose's docs/packages.md). What a user of the package
# links is goose_gfx2d_package.

cmake_minimum_required(VERSION 3.20)
project(goose_gfx2d_package C)

# stb: the submodule beside this file. Without it the package builds
# nothing, and says so.
set(GOOSE_GFX2D_stb "" CACHE PATH "The stb source tree")
if(NOT GOOSE_GFX2D_stb)
    set(GOOSE_GFX2D_stb "${CMAKE_CURRENT_SOURCE_DIR}/third_party/stb")
endif()
if(NOT EXISTS "${GOOSE_GFX2D_stb}/stb_truetype.h")
    message(STATUS "gfx2d: stb not found (the third_party/stb submodule); building nothing")
    return()
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
