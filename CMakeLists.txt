include(${CMAKE_SOURCE_DIR}/cmake/pr_common.cmake)

set(PROJ_NAME pr_davinci)
pr_add_module(${PROJ_NAME} "addons/davinci/modules/davinci/")

pr_add_dependency(${PROJ_NAME} shared TARGET PUBLIC)

pr_init_module(${PROJ_NAME})

pr_finalize(${PROJ_NAME})
