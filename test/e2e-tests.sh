#!/usr/bin/env bash

set -ex
set -o pipefail

# Configure the number of parallel tests running at the same time
MAX_NUMBERS_OF_PARALLEL_TASKS=7

export RELEASE_YAML=https://github.com/tektoncd/pipeline/releases/download/v0.57.0/release.yaml

source $(dirname $0)/../vendor/github.com/tektoncd/plumbing/scripts/e2e-tests.sh
source $(dirname $0)/e2e-common.sh

E2E_SKIP_CLUSTER_CREATION=${E2E_SKIP_CLUSTER_CREATION:="false"}

TMPF=$(mktemp /tmp/.mm.XXXXXX)
clean() { rm -f ${TMPF}; }
trap clean EXIT

# Setup a test cluster
[[ -z ${LOCAL_CI_RUN} ]] && {
    if [ "${E2E_SKIP_CLUSTER_CREATION}" != "true" ]; then
        initialize "$@"
    fi
    install_pipeline_crd
}

TEST_YAML_IGNORES=${TEST_YAML_IGNORES:-""}
TEST_TASKRUN_IGNORES=${TEST_TASKRUN_IGNORES:-"maven"}
TEST_RUN_ALL_TESTS=${TEST_RUN_ALL_TESTS:-""}

all_stepactions=$(echo stepaction/*/*/tests)
all_tests=$(echo task/*/*/tests)

function detect_changed_e2e_test() {
    git --no-pager diff --name-only "${PULL_BASE_SHA}".."${PULL_PULL_SHA}" | grep "^test/[^/]*"
}

[[ -z ${TEST_RUN_ALL_TESTS} ]] && [[ ! -z $(detect_changed_e2e_test) ]] && TEST_RUN_ALL_TESTS=1

function detect_new_changed_resources() {
    git --no-pager diff --name-only "${PULL_BASE_SHA}".."${PULL_PULL_SHA}" | grep 'task/[^\/]*/[^\/]*/tests/[^/]*' | xargs -I {} dirname {} | sed 's/\(tests\).*/\1/g'
    git --no-pager diff --name-only "${PULL_BASE_SHA}".."${PULL_PULL_SHA}" | grep 'task/[^\/]*/[^\/]*/*[^/]*.yaml' | xargs -I {} dirname {} | awk '{print $1"/tests"}'
    git --no-pager diff --name-only "${PULL_BASE_SHA}".."${PULL_PULL_SHA}" | grep 'stepaction/[^\/]*/[^\/]*/tests/[^/]*' | xargs -I {} dirname {} | sed 's/\(tests\).*/\1/g'
    git --no-pager diff --name-only "${PULL_BASE_SHA}".."${PULL_PULL_SHA}" | grep 'stepaction/[^\/]*/[^\/]*/*[^/]*.yaml' | xargs -I {} dirname {} | awk '{print $1"/tests"}'
}

if [[ -z ${TEST_RUN_ALL_TESTS} ]]; then
    all_tests=$(detect_new_changed_resources | sort -u || true)
    [[ -z ${all_tests} ]] && {
        echo "No tests detected in this PR. Exiting."
        success
    }
fi

test_yaml_can_install "${all_stepactions}"

# OVERRIDE for specific test directory
if [[ -n "$ONLY_TEST" ]]; then
    echo "ONLY_TEST mode enabled: $ONLY_TEST"
    all_tests="$ONLY_TEST"
fi

test_yaml_can_install "${all_tests}"

function test_resources {
    local cnt=0
    local resource_to_tests=""

    for runtest in $@; do
        resource_to_tests="${resource_to_tests} ${runtest}"
        if [[ ${cnt} == "${MAX_NUMBERS_OF_PARALLEL_TASKS}" ]]; then
            test_resource_creation "${resource_to_tests}"
            cnt=0
            resource_to_tests=""
            continue
        fi
        cnt=$((cnt+1))
    done

    if [[ -n ${resource_to_tests} ]]; then
        test_resource_creation "${resource_to_tests}"
    fi
}

test_resources "${all_stepactions}"
test_resources "${all_tests}"

success
