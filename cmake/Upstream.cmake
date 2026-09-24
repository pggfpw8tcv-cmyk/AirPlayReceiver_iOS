# Build only the receiver core, never UxPlay's desktop application/renderers.
set(SOURCES_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.deps/src")
set(UX "${SOURCES_ROOT}/uxplay/lib")
set(PL "${SOURCES_ROOT}/libplist")
file(GLOB PLIST_SOURCES CONFIGURE_DEPENDS "${PL}/src/*.c" "${PL}/libcnary/*.c")
add_library(plist STATIC ${PLIST_SOURCES})
target_include_directories(plist PUBLIC "${PL}/include" PRIVATE "${PL}/src" "${PL}/libcnary/include")
target_compile_definitions(plist PRIVATE PACKAGE_VERSION="2.7.0" HAVE_STRNDUP HAVE_MEMMEM
  HAVE_STRPTIME HAVE_LOCALTIME_R HAVE_GMTIME_R HAVE_TM_TM_GMTOFF HAVE_TM_TM_ZONE)

file(GLOB UX_SOURCES CONFIGURE_DEPENDS "${UX}/*.c" "${UX}/playfair/*.c" "${UX}/llhttp/*.c")
# Upstream assumes init2 succeeded before destruction; an embedded app must also
# release a partially initialized instance. Preserve pristine downloaded sources.
file(READ "${UX}/raop.c" RAOP_SOURCE)
string(REPLACE "    httpd_stop(raop->httpd);" "    if (raop->httpd) httpd_stop(raop->httpd);" RAOP_PATCHED "${RAOP_SOURCE}")
if(RAOP_SOURCE STREQUAL RAOP_PATCHED)
  message(FATAL_ERROR "UxPlay partial-init patch no longer matches the pinned source")
endif()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/raop_ios.c" "${RAOP_PATCHED}")
list(REMOVE_ITEM UX_SOURCES "${UX}/raop.c")
list(APPEND UX_SOURCES "${CMAKE_CURRENT_BINARY_DIR}/raop_ios.c")
add_library(uxplay STATIC ${UX_SOURCES})
target_include_directories(uxplay PUBLIC "${UX}" PRIVATE "${UX}/playfair" "${UX}/llhttp")
target_compile_definitions(uxplay PRIVATE PLIST_210 PLIST_230 OPENSSL_API_COMPAT=0x10101000L)
target_link_libraries(uxplay PUBLIC plist OpenSSL::Crypto)
if(NOT APPLE)
  target_link_libraries(uxplay PUBLIC pthread m)
endif()
install(TARGETS uxplay plist ARCHIVE DESTINATION lib)
