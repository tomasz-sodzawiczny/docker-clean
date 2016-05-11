#!/usr/bin/env bats

# PRODUCTION Bats Tests for Travis CI

# Initial pass at testing for docker-clean
# These tests simply test each of the options currently available

# To run the tests locally run brew install bats or
# sudo apt-get install bats and then bats batsTest.bats

# WARNING: Runing these tests will clear all of your images/Containers

@test "Check that docker client is available" {
  command -v docker
  #[ $status = 0 ]
}

@test "Run docker ps (check daemon connectivity)" {
  run docker ps
  [ $status = 0 ]
}

@test "Docker Clean Version echoes" {
  run ./docker-clean -v
  [ $status = 0 ]
}

@test "Default build and clean testing helper functions" {
  build
  [ $status = 0 ]

  clean
  runningContainers="$(docker ps -aq)"
  [ ! $runningContainers ]
  }

@test "Help menu opens" {
  # On -h flag
  run ./docker-clean -h
  [[ ${lines[0]} =~ "Options:" ]]
  run ./docker-clean --help
  [[ ${lines[0]} =~ "Options:" ]]

  # On unspecified tag
  run ./docker-clean -z
  [[ ${lines[0]} =~ "Options:" ]]
  #clean
}

# Runs most powerful command and confirms nothing cleaned
@test "Test Dry Run (runs most powerful removal command in dry run)" {
    buildWithVolumes
    [ $status = 0 ]
    runningContainers="$(docker ps -aq)"
    stoppedContainers="$(docker ps -qf STATUS=exited )"
    untaggedImages="$(docker images -aq --filter "dangling=true")"
    listedImages="$(docker images -aq)"
    volumes="$(docker volume ls -q)"

    # Run command with most power
    run ./docker-clean all --dry-run
    [ $status = 0 ]

    afterRunningContainers="$(docker ps -aq)"
    afterStoppedContainers="$(docker ps -qf STATUS=exited )"
    afterUntaggedImages="$(docker images -aq --filter "dangling=true")"
    afterListedImages="$(docker images -aq)"
    afterVolumes="$(docker volume ls -q)"
    [[ $runningContainers == $afterRunningContainers ]]
    [[ $stoppedContainers == $afterStoppedContainers ]]
    [[ $untaggedImages == $afterUntaggedImages ]]
    [[ $listedImages == $afterListedImages ]]
    [[ $volumes == $afterVolumes ]]
    clean
}

@test "Test network removal" {
    build
    [ $status = 0 ]
    run docker network create one
    run docker network create two
    run docker network connect testNet container
    run ./docker-clean --networks

    used="$(docker network ls -qf name='one')"
    empty="$(docker network ls -qf name='two')"
    [[ $used ]]
    [[ -z $empty ]]

}

@test "Test container stopping (-s --stop)" {
  build
  [ $status = 0 ]
  runningContainers="$(docker ps -q)"
  [ $runningContainers ]
  run ./docker-clean -s
  runningContainers="$(docker ps -q)"
  [ ! $runningContainers ]

  clean
}

@test "Clean Containers test" {
  stoppedContainers="$(docker ps -a)"
  untaggedImages="$(docker images -aq --filter "dangling=true")"
  run docker kill $(docker ps -a -q)
  [ "$stoppedContainers" ]

  run ./docker-clean
  stoppedContainers="$(docker ps -qf STATUS=exited )"
  createdContainers="$(docker ps -qf STATUS=created)"
  [ ! "$stoppedContainers" ]
  [ ! "$createdContainers" ]

  clean
}

@test "Clean All Containers Test" {
  build
  [ $status = 0 ]
  allContainers="$(docker ps -a -q)"
  [ "$allContainers" ]
  run ./docker-clean -s -c
  allContainers="$(docker ps -a -q)"
  [ ! "$allContainers" ]

  clean
}

@test "Force-remove all Containers Test" {
  build
  [ $status = 0 ]
  allContainers="$(docker ps -a -q)"
  [ "$allContainers" ]
  run ./docker-clean -f
  allContainers="$(docker ps -a -q)"
  [ ! "$allContainers" ]

  clean
}

# TODO: create an untagged image test case
@test "Clean images (not all)" {
  skip
  build
  [ $status = 0 ]
  untaggedImages="$(docker images -aq --filter "dangling=true")"
  [ "$untaggedImages" ]

  run ./docker-clean
  untaggedImages="$(docker images -aq --filter "dangling=true")"
  [ ! "$untaggedImages" ]

  clean
}

@test "Clean all function for images" {
  build
  [ $status = 0 ]
  listedImages="$(docker images -aq)"
  [ "$listedImages" ]

  run ./docker-clean -a
  listedImages="$(docker images -aq)"
  [ ! "$listedImages" ]

  clean
}

@test "Clean Volumes function" {
  buildWithVolumes
  [ $status = 0 ]
  run docker stop extra
  volumes="$(docker volume ls -q)"
  [ "$volumes" ]
  run docker rm -f extra
  clean
}


# TODO test case for the -qf STATUS exited
# TODO Write test with an untagged image
@test "Default run through -- docker-clean (without arguments)" {
  build
  [ $status = 0 ]
  stoppedContainers="$(docker ps -a)"
  untaggedImages="$(docker images -aq --filter "dangling=true")"
  run docker kill $(docker ps -a -q)
  [ "$stoppedContainers" ]

  #[ "$untaggedImages" ]
  run ./docker-clean

  #stoppedContainers="$(docker ps -qf STATUS=exited )"
  #createdContainers="$(docker ps -qf STATUS=created)"
  danglingVolumes="$(docker volume ls -qf dangling=true)"
  [ ! "$danglingVolumes" ]
  [ "$stoppedContainers" ]
  #[ ! "$createdContainers" ]
  #[ ! "$untaggedImages" ]

  clean
}

# Test for counting correctly
@test "Testing counting function" {
  build
  [ $status = 0 ]
  run docker kill $(docker ps -a -q)
  run ./docker-clean -s -c
  [[ $output =~ "Cleaning containers" ]]
  [[ $output =~ "1" ]]
  build
  run docker run -d -P --name web -v /webapp training/webapp python app.py
  run ./docker-clean -s -c
  [[ $output =~ "Cleaning containers" ]]
  [[ $output =~ "2" ]]
  #run ./docker-clean -i
  #[[ $output =~ "Cleaning images..."  ]]
  #[[ $output =~ "4" ]]
  clean
}

# Tests logging outputs properly
@test "Verbose log function (-l --log)" {
    build
    [ $status = 0 ]
    docker stop "$(docker ps -q)"
    stoppedContainers="$(docker ps -a -q)"
    run ./docker-clean -c -l 2>&1
    [[ $output =~ "$stoppedContainers" ]]

    clean
}
# Testing for successful restart
@test "Restart function" {
    operating_system=$(testOS)
    if [[ $operating_system =~ "mac" || $operating_system =~ 'windows' ]]; then
      ./docker-clean -a | grep 'started'
      run docker ps &>/dev/null
      [ $status = 0 ]
    elif [[ $operating_system =~ "linux" ]]; then
      ./docker-clean -a | grep 'stop'
      #ps -e | grep 'docker'

      run docker ps &>/dev/null
      [ $status = 0 ]
    else
      echo "Operating system not valid"
      [[ false ]]
    fi
}

# Helper FUNCTIONS

function build() {
    if [ $(docker ps -a -q) ]; then
      docker rm -f $(docker ps -a -q)
    fi
    run docker pull zzrot/whale-awkward
    run docker pull zzrot/alpine-ghost
    run docker pull zzrot/alpine-node
    run docker run -d --name container zzrot/alpine-caddy
}

function buildWithVolumes {
    if [ $(docker ps -a -q) ]; then
        docker rm -f $(docker ps -a -q)
    fi
    run docker pull zzrot/whale-awkward
    run docker pull zzrot/alpine-ghost
    run docker run -d -P --name extra -v /webapp zzrot/alpine-caddy
}

function clean() {
  run docker kill $(docker ps -a -q)
  run docker rm -f $(docker ps -a -q)
  run docker rmi -f $(docker images -aq)
}

## ** Script for testing os **
# Credit https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux/17072017#17072017?newreg=b1cdf253d60546f0acfb73e0351ea8be
# Echo mac for Mac OS X, echo linux for GNU/Linux, echo windows for Window
function testOS {
  if [ "$(uname)" == "Darwin" ]; then
      # Do something under Mac OS X platform
      echo mac
  elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
      # Do something under GNU/Linux platform
      echo linux
  elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
      # Do something under Windows NT platform
      echo windows
  fi
}
