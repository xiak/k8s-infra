#!/bin/bash

# Copyright 2019 xiak.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This file creates release artifacts (tar files, container images) that are
# ready to distribute to install or distribute to end users.


# ASCII color codes
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_PURPLE="\033[35m"
COLOR_SKYBLUE="\033[36m"

# Reset color code
COLOR_CLEAR="\033[0m"

# Print and return
function fmt::println() {
    printf "${1}\n"
}

# Print
function fmt::print() {
    printf "${1}"
}

# Print process
# fmt::process "Begin"
# doSomething
# fmt::ok "Done"
# Output
# >>> Begin: Done
function fmt::process() {
    printf ">>> ${1}: "
}

# Print remote execution - yellow
# fmt::printh 10.62.232.66 "Hello World"
# Output
# 10.62.232.66: Hello World
function fmt::remote() {
    printf "${COLOR_YELLOW}${1}: ${2}${COLOR_CLEAR}\n"
}

# Print info msg - skyblue
# fmt::info "Hello"
# Output
# Hello
function fmt::info() {
    printf "${COLOR_SKYBLUE}INFO ${1}${COLOR_CLEAR}\n"
}

# Print debug msg - blue
# fmt::debug "Hello"
# Output
# Hello
function fmt::debug() {
    printf "${COLOR_PURPLE}DEBUG ${1}${COLOR_CLEAR}\n"
}

# Print error msg - red
# fmt::error "Hello"
# Output
# Hello
function fmt::error() {
    printf "${COLOR_RED}ERROR ${1}${COLOR_CLEAR}\n"
}

# Print warning msg - yellow
# fmt::warn "Hello"
# Output
# Hello
function fmt::warn() {
    printf "${COLOR_YELLOW}WARN ${1}${COLOR_CLEAR}\n"
}

# Print fatal msg and then exit script - red
# fmt::fatal "Hello"
# Output
# Hello
function fmt::fatal() {
    printf "${COLOR_RED}FATAL ${1}${COLOR_CLEAR}\n"
    exit 1
}

# Print well done msg - green
# fmt::ok "Done"
# Output
# Done
function fmt::ok() {
    printf "${COLOR_GREEN}${1}${COLOR_CLEAR}\n"
}

# Print well done msg - red
# fmt::fail "Fail"
# Output
# Fail
function fmt::fail() {
    printf "${COLOR_RED}${1}${COLOR_CLEAR}\n"
}


# Unit test
function test() {
    fmt::println "Hello world"
    fmt::print "Hello world\n"
    fmt::process "Started"
    Sleep 1s
    fmt::ok "Done"
    fmt::remote "10.62.232.66" "Service started"
    fmt::info "Hello world"
    fmt::debug "{code: 200, message: \"Hello world\"}"
    fmt::error "Can't parse json file"
    fmt::warn "Timeout"
    fmt::ok "Done"
    fmt::fail "Fail"
    fmt::fatal "Out of memory"

}

