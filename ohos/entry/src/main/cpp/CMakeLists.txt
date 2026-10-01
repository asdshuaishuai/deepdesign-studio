cmake_minimum_required(VERSION 3.5.1)
project(deepdesign_native)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
  set(OHOS_ARCH arm64-v8a)
else()
  set(OHOS_ARCH x86_64)
endif()

set(RUST_SO ${CMAKE_CURRENT_SOURCE_DIR}/rust-libs/${OHOS_ARCH}/libdeepdesign_core.so)
file(MAKE_DIRECTORY ${CMAKE_LIBRARY_OUTPUT_DIRECTORY})

add_custom_target(copy_rust_core ALL
  COMMAND ${CMAKE_COMMAND} -E copy_if_different ${RUST_SO} ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libdeepdesign_core.so
  DEPENDS ${RUST_SO}
  COMMENT "deploy rust core so (${OHOS_ARCH})")
