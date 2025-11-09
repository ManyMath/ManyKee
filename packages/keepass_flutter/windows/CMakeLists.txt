cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "keepass_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# cargokit integration
include(../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PROJECT_NAME} ../rust keepass_flutter_native kpxc_database_open)
set(${PROJECT_NAME}_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
