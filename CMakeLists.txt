cmake_minimum_required(VERSION 3.4.3)
if(POLICY CMP0025)
    cmake_policy(SET CMP0025 NEW)
endif()
if(${CMAKE_VERSION} VERSION_GREATER "3.26.9")
    # Prevent implicit dependencies for custom commands, e.g.,
    # `obj/ldc2.o` depending on `lib/libldc.a` with LDC_LINK_MANUALLY=ON.
    # Only supported since CMake v3.27 unfortunately.
    set(CMAKE_ADD_CUSTOM_COMMAND_DEPENDS_EXPLICIT_ONLY ON)
endif()

# Special case for Meson because it can't build subdirectories
if(DEFINED DRUNTIME_ONLY)
    add_subdirectory(runtime)
else()
    project(ldc)
    include(upstream.cmake)
endif()
