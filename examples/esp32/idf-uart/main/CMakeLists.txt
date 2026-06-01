idf_component_register(SRCS "app_main.c")

# nurl_uart.nu (+ stdlib/hal/*) --(nurlc)--> .ll --(esp-clang -O0)--> .o
set(NURL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../nurl")
set(NURL_OBJ "${NURL_DIR}/nurl_uart.o")
add_custom_command(
    OUTPUT  "${NURL_OBJ}"
    COMMAND "${NURL_DIR}/gen_object.sh"
    DEPENDS "${NURL_DIR}/nurl_uart.nu" "${NURL_DIR}/gen_object.sh"
    COMMENT "NURL -> Xtensa object (nurlc + esp-clang, -O0)"
    VERBATIM)
add_custom_target(nurl_uart_obj DEPENDS "${NURL_OBJ}")
add_dependencies(${COMPONENT_LIB} nurl_uart_obj)
target_link_libraries(${COMPONENT_LIB} PRIVATE "${NURL_OBJ}")
