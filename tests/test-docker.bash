#!/usr/bin/env bash
# Prepare retained, non-root M2 environments in pinned Docker base images.
set -euo pipefail

SCRIPT_DIR=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
readonly SCRIPT_DIR SOURCE_ROOT="${SCRIPT_DIR%/*}"
readonly EVIDENCE_ROOT="${SOURCE_ROOT}/work/m2-verification"
readonly IMAGE_VERSION=1.5.0 PULL_TIMEOUT=600 BUILD_TIMEOUT=900 PREFLIGHT_TIMEOUT=180
readonly -a ALL_TARGETS=(debian13 debian12 rocky8 rocky10 ubuntu24 ubuntu26)
declare -a targets=()
declare -g run_dir="" container_id="" active_target="" complete=0
declare -i incomplete=0
# shellcheck source=tests/docker-capture.bash
source "${SCRIPT_DIR}/docker-capture.bash"

function usage {
    printf '%s\n' 'Usage: bash tests/test-docker.bash [TARGET ...]' \
        'Targets: debian13 debian12 rocky8 rocky10 ubuntu24 ubuntu26' \
        'No targets selects all six. Only preparation runs; no IOC acceptance suite.' \
        'Builds local test images with ripgrep and Rocky diffutils from pinned base images.' \
        'Exit: 0 preparation ready, 2 incomplete preparation/usage; signals retain 130/143.'
}

function finish {
    local native=$? final=0 cleanup_status=0
    trap - EXIT
    final=${native}
    if [[ -n "${container_id}" ]]; then
        docker stop --time 5 "${container_id}" > "${run_dir}/${active_target}/emergency-stop.stdout" \
            2> "${run_dir}/${active_target}/emergency-stop.stderr" || cleanup_status=$?
        if ! printf '%s\n' "${cleanup_status}" > "${run_dir}/${active_target}/emergency-stop.status"; then
            [[ ${final} -ne 0 ]] || final=2
        fi
        printf 'Retained container after interrupted preparation: %s\n' "${container_id}" >&2
        incomplete=$((incomplete + 1))
    fi
    if [[ ${complete} -ne 1 || ${incomplete} -gt 0 ]]; then
        [[ ${final} -ne 0 ]] || final=2
    fi
    if [[ -n "${run_dir}" ]]; then
        if ! printf 'Scope: preparation only\nComplete: %s\nIncomplete targets: %s\nNative status: %s\nExit status: %s\n' \
            "${complete}" "${incomplete}" "${native}" "${final}" > "${run_dir}/result.txt"; then
            [[ ${final} -ne 0 ]] || final=2
        fi
        printf 'Evidence: %s\n' "${run_dir}"
    fi
    exit "${final}"
}

function record_incomplete {
    local target="$1" reason="$2"
    incomplete=$((incomplete + 1))
    printf '%s\tIncomplete\t%s\n' "${target}" "${reason}" >> "${run_dir}/coverage.tsv"
    printf '[ INCOMPLETE ] %s: %s\n' "${target}" "${reason}"
}

function prepare_target {
    local target="$1" image="jeonghanlee/${1}-epics:${IMAGE_VERSION}" pinned=""
    local state="" worker_status="" start_status=0 path="${run_dir}/${1}" test_image=""
    mkdir -p -- "${path}/commands" "${path}/evidence" "${path}/workspace"
    RECEIPTS="${path}/commands"
    printf 'Why: verify the actual %s image before IOC test execution.\n' "${target}"
    capture pull timeout "${PULL_TIMEOUT}" docker pull "${image}"
    if [[ ${CAPTURE_STATUS} -ne 0 ]]; then record_incomplete "${target}" 'Image pull failed'; return; fi
    capture image-inspect docker image inspect "${image}"
    if [[ ${CAPTURE_STATUS} -ne 0 ]]; then record_incomplete "${target}" 'Image inspection failed'; return; fi
    capture digest docker image inspect --format '{{index .RepoDigests 0}}' "${image}"
    if [[ ${CAPTURE_STATUS} -ne 0 ]]; then record_incomplete "${target}" 'Digest unavailable'; return; fi
    IFS= read -r pinned < "${RECEIPTS}/digest/stdout"
    if [[ ! "${pinned}" =~ ^jeonghanlee/${target}-epics@sha256:[a-f0-9]{64}$ ]]; then
        record_incomplete "${target}" 'Unexpected digest identity'; return
    fi
    capture distribution-label docker image inspect --format '{{index .Config.Labels "epics.distribution-version"}}' "${pinned}"
    if [[ ${CAPTURE_STATUS} -ne 0 || "$(< "${RECEIPTS}/distribution-label/stdout")" != "${IMAGE_VERSION}" ]]; then
        record_incomplete "${target}" 'Distribution label is not 1.5.0'; return
    fi
    source_inventory "${run_dir}/source" "${run_dir}/inventory/members.nul" > "${path}/source-before.tsv"
    find "${run_dir}/source" \( -type f -o -type l \) -printf '%P\0' | LC_ALL=C sort -z > "${path}/members-before.nul"
    cmp -- "${run_dir}/inventory/members.nul" "${path}/members-before.nul"
    cmp -- "${run_dir}/inventory/source.tsv" "${path}/source-before.tsv"
    capture build timeout "${BUILD_TIMEOUT}" docker build --progress plain \
        --build-arg "BASE_IMAGE=${pinned}" --iidfile "${path}/test-image.id" \
        "${run_dir}/source/tests/docker"
    if [[ ${CAPTURE_STATUS} -ne 0 ]]; then record_incomplete "${target}" 'Test image build failed'; return; fi
    test_image=$(cat -- "${path}/test-image.id")
    [[ "${test_image}" =~ ^sha256:[a-f0-9]{64}$ ]] || return 2
    capture test-image-inspect docker image inspect "${test_image}"
    [[ ${CAPTURE_STATUS} -eq 0 ]] || return 2
    capture test-image-base docker image inspect --format '{{index .Config.Labels "tools.m2.base-image"}}' "${test_image}"
    if [[ ${CAPTURE_STATUS} -ne 0 || "$(< "${RECEIPTS}/test-image-base/stdout")" != "${pinned}" ]]; then
        record_incomplete "${target}" 'Test image base identity mismatch'; return
    fi
    capture create docker create --network none --user "$(id -u):$(id -g)" \
        --cap-drop ALL --security-opt no-new-privileges \
        --mount "type=bind,src=${run_dir}/source,dst=/src,readonly" \
        --mount "type=bind,src=${path}/evidence,dst=/evidence" \
        --mount "type=bind,src=${path}/workspace,dst=/work" \
        --workdir /work --env USER=m2-test --env LOGNAME=m2-test \
        --entrypoint /bin/bash "${test_image}" /src/tests/docker-preflight.bash "${target}"
    if [[ ${CAPTURE_STATUS} -ne 0 ]]; then record_incomplete "${target}" 'Container creation failed'; return; fi
    IFS= read -r container_id < "${RECEIPTS}/create/stdout"
    [[ "${container_id}" =~ ^[a-f0-9]{64}$ ]] || return 2
    active_target=${target}
    capture start timeout "${PREFLIGHT_TIMEOUT}" docker start --attach "${container_id}"
    start_status=${CAPTURE_STATUS}
    capture container-inspect docker inspect "${container_id}"
    [[ ${CAPTURE_STATUS} -eq 0 ]] || return 2
    capture state docker inspect --format '{{.State.Running}} {{.State.ExitCode}}' "${container_id}"
    if [[ ${CAPTURE_STATUS} -ne 0 ]]; then return 2; fi
    read -r state worker_status < "${RECEIPTS}/state/stdout"
    if [[ "${state}" != false ]]; then
        record_incomplete "${target}" 'Preflight did not terminate; container retained'
        return 2
    fi
    capture logs docker logs "${container_id}"
    if [[ ${CAPTURE_STATUS} -ne 0 ]]; then return 2; fi
    source_inventory "${run_dir}/source" "${run_dir}/inventory/members.nul" > "${path}/source-after.tsv"
    find "${run_dir}/source" \( -type f -o -type l \) -printf '%P\0' | LC_ALL=C sort -z > "${path}/members-after.nul"
    cmp -- "${run_dir}/inventory/members.nul" "${path}/members-after.nul"
    cmp -- "${run_dir}/inventory/source.tsv" "${path}/source-after.tsv"
    if [[ ${start_status} -eq 0 && "${worker_status}" == 0 && -s "${path}/evidence/result.txt" ]] &&
        grep -qxF 'Verdict: Passed' "${path}/evidence/result.txt"; then
        printf '%s\tPassed\tPreparation only\n' "${target}" >> "${run_dir}/coverage.tsv"
        printf '[ PASS ] %s preparation\n' "${target}"
    else
        record_incomplete "${target}" "Preflight native status ${worker_status}; launcher ${start_status}"
    fi
    capture remove docker rm "${container_id}"
    [[ ${CAPTURE_STATUS} -eq 0 ]] || return 2
    container_id=""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --) shift; targets+=("$@"); break ;;
        -*) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
        *) targets+=("$1") ;;
    esac
    shift
done
if [[ ${#targets[@]} -eq 0 ]]; then targets=("${ALL_TARGETS[@]}"); fi
declare -A seen=()
for target in "${targets[@]}"; do
    case "${target}" in debian13|debian12|rocky8|rocky10|ubuntu24|ubuntu26) ;; *) printf 'Unknown target: %s\n' "${target}" >&2; exit 2 ;; esac
    [[ -z "${seen[${target}]:-}" ]] || { printf 'Duplicate target: %s\n' "${target}" >&2; exit 2; }
    seen[${target}]=1
done
for tool in docker git tar find sort stat readlink sha256sum cmp timeout; do
    tool_path=$(command -v "${tool}")
    [[ -x "${tool_path}" ]] || exit 2
done
[[ $(id -u) -ne 0 ]] || { printf 'Run as a non-root Docker client user.\n' >&2; exit 2; }
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p -- "${EVIDENCE_ROOT}"
run_dir=$(mktemp -d "${EVIDENCE_ROOT}/docker.XXXXXXXX")
mkdir -- "${run_dir}/inventory" "${run_dir}/source" "${run_dir}/commands"
RECEIPTS="${run_dir}/commands"
printf 'Target\tVerdict\tReason\n' > "${run_dir}/coverage.tsv"
printf '%s\n' "${targets[@]}" > "${run_dir}/inventory/targets"
capture docker-version docker version
[[ ${CAPTURE_STATUS} -eq 0 ]] || exit 2
capture git-status git -C "${SOURCE_ROOT}" status --porcelain=v1 --branch
[[ ${CAPTURE_STATUS} -eq 0 ]] || exit 2
capture git-head git -C "${SOURCE_ROOT}" rev-parse HEAD
[[ ${CAPTURE_STATUS} -eq 0 ]] || exit 2
git -C "${SOURCE_ROOT}" ls-files -z --cached --others --exclude-standard > "${run_dir}/inventory/git-members.nul"
LC_ALL=C sort -z "${run_dir}/inventory/git-members.nul" > "${run_dir}/inventory/members.nul"
source_inventory "${SOURCE_ROOT}" "${run_dir}/inventory/members.nul" > "${run_dir}/inventory/source.tsv"
tar -C "${SOURCE_ROOT}" --null --no-recursion -T "${run_dir}/inventory/members.nul" -cf "${run_dir}/source.tar"
tar -C "${run_dir}/source" -xf "${run_dir}/source.tar"
find "${run_dir}/source" \( -type f -o -type l \) -printf '%P\0' | LC_ALL=C sort -z > "${run_dir}/inventory/copied-members.nul"
cmp -- "${run_dir}/inventory/members.nul" "${run_dir}/inventory/copied-members.nul"
source_inventory "${run_dir}/source" "${run_dir}/inventory/members.nul" > "${run_dir}/inventory/copied-source.tsv"
cmp -- "${run_dir}/inventory/source.tsv" "${run_dir}/inventory/copied-source.tsv"
sha256sum "${run_dir}/inventory/"* "${run_dir}/source.tar" > "${run_dir}/inventory.sha256"
for target in "${targets[@]}"; do prepare_target "${target}"; done
complete=1
