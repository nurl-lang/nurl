idf_component_register(SRCS "app_main.c")

# Compile the NURL module to a Xtensa object as part of the build:
#   nurl_blink.nu --(nurlc)--> .ll --(esp-clang xtensa-esp32-elf)--> .o
# Regenerated automatically whenever nurl_blink.nu changes.
set(NURL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../nurl")
set(NURL_OBJ "${NURL_DIR}/nurl_blink.o")

add_custom_command(
    OUTPUT  "${NURL_OBJ}"
    COMMAND "${NURL_DIR}/gen_object.sh"
    DEPENDS "${NURL_DIR}/nurl_blink.nu" "${NURL_DIR}/gen_object.sh"
    COMMENT "NURL -> Xtensa object (nurlc + esp-clang)"
    VERBATIM)
add_custom_target(nurl_blink_obj DEPENDS "${NURL_OBJ}")
add_dependencies(${COMPONENT_LIB} nurl_blink_obj)

# An object file on the link line is always pulled in, so the nurl_*
# symbols referenced by app_main.c resolve against it.
target_link_libraries(${COMPONENT_LIB} PRIVATE "${NURL_OBJ}")
