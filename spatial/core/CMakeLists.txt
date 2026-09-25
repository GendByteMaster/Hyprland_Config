cmake_minimum_required(VERSION 3.20)
project(gendbyte_spatial_core LANGUAGES CXX)

option(SPATIAL_BUILD_PLUGIN "Build the Hyprland plugin adapter" OFF)
option(SPATIAL_BUILD_TESTS "Build pure spatial core tests" ON)

add_library(spatial_core STATIC
    src/Camera.cpp
    src/SpatialState.cpp
)

target_include_directories(spatial_core PUBLIC include)
target_compile_features(spatial_core PUBLIC cxx_std_20)
target_compile_options(spatial_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion)

if(SPATIAL_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(SPATIAL_BUILD_PLUGIN)
    message(FATAL_ERROR "SPATIAL_BUILD_PLUGIN is reserved for Task 4 and is not implemented yet")
endif()
