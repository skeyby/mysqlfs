cmake_minimum_required(VERSION 3.10)
project (MySQLfs)

# The version number.
set (MySQLfs_VERSION_MAJOR 1)
set (MySQLfs_VERSION_MINOR 0)
set (MySQLfs_VERSION_PATCH 3)

MESSAGE(STATUS "Compiling MySQLfs ${MySQLfs_VERSION_MAJOR}.${MySQLfs_VERSION_MINOR}.${MySQLfs_VERSION_PATCH} on ${CMAKE_SYSTEM}")

set(CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR})

FIND_PACKAGE(MySQL)
IF(MYSQL_FOUND)
    MESSAGE(STATUS "MySQL found at: ${MYSQL_INCLUDE_DIR}, ${MYSQL_LIBRARIES}")
ELSE(MYSQL_FOUND)
    MESSAGE(SEND_ERROR "Couldn't find MySQL include files and/or library")
ENDIF(MYSQL_FOUND)

set(MYSQL_MIN_VERSION 5000)

find_package(FUSE 2.6 REQUIRED)
if(FUSE_FOUND)
    MESSAGE(STATUS "FUSE found at: ${FUSE_INCLUDE_DIRS}, ${FUSE_LIBRARIES}")
endif()

set(FUSE_USE_VERSION 26)

find_package( LibM REQUIRED )
IF(LibM_FOUND)
    MESSAGE(STATUS "LibM found at: ${LibM_LIBRARY_DIR}, ${LibM_LIBRARIES}")
ELSE(LibM_FOUND)
    MESSAGE(SEND_ERROR "Couldn't find LibM include files and/or library")
ENDIF(LibM_FOUND)


# configure a header file to pass some of the CMake settings
# to the source code
MESSAGE(STATUS "Writing ${PROJECT_SOURCE_DIR}/src/Config.h.in to ${PROJECT_BINARY_DIR}/Config.h")
configure_file (
          "${PROJECT_SOURCE_DIR}/src/Config.h.in"
          "${PROJECT_BINARY_DIR}/Config.h"
)


# add the binary tree to the search path for include files
# so that we will find TutorialConfig.h
include_directories("${PROJECT_BINARY_DIR}")

add_definitions(${FUSE_DEFINITIONS})

include_directories(${FUSE_INCLUDE_DIRS})
include_directories(${MYSQL_INCLUDE_DIR})

SET( CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -lm")

add_subdirectory(src)

FILE(GLOB files "${PROJECT_SOURCE_DIR}/src/sql/updates/*.sql")
MESSAGE(STATUS "SQL updates: ${files}")

install(FILES "mysqlfs_setup" PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ DESTINATION bin)
install(FILES ${files} DESTINATION share/mysqlfs/sql/update)
