cmake_minimum_required(VERSION 3.10)
project(fasttext_bridge)

add_library(fasttext_bridge SHARED fasttext_bridge.cpp)

find_library(log-lib log)

target_link_libraries(fasttext_bridge ${log-lib})
