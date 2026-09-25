cmake_minimum_required(VERSION 3.20)
project(gendbyte_spatial_core LANGUAGES CXX)

option(SPATIAL_BUILD_PLUGIN "Build the Hyprland plugin adapter" OFF)
option(SPATIAL_BUILD_TESTS "Build pure spatial core tests" ON)

add_library(spatial_core STATIC
    src/Camera.cpp
    src/SpatialState.cpp
    src/Protocol.cpp
    src/Command.cpp
)

target_include_directories(spatial_core PUBLIC include)
target_compile_features(spatial_core PUBLIC cxx_std_20)
target_compile_options(spatial_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion)
set_target_properties(spatial_core PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(SPATIAL_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(SPATIAL_BUILD_PLUGIN)
    find_package(PkgConfig REQUIRED)

    pkg_check_modules(hyprland_deps REQUIRED IMPORTED_TARGET
        hyprland
        libdrm
        libinput
        libudev
        pangocairo
        pixman-1
        wayland-server
        xkbcommon
    )

    add_library(gendbyte-spatial SHARED src/plugin.cpp)
    target_link_libraries(gendbyte-spatial PRIVATE spatial_core rt PkgConfig::hyprland_deps)
    target_compile_features(gendbyte-spatial PRIVATE cxx_std_23)
    target_compile_options(gendbyte-spatial PRIVATE -Wall -Wextra -Wpedantic)
    set_target_properties(gendbyte-spatial PROPERTIES
        PREFIX ""
        OUTPUT_NAME "gendbyte-spatial"
    )
endif()
