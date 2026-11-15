# Capture one real command without replacing its native outcome.
declare -g CAPTURE_STATUS=0 RECEIPTS=""

function capture {
    local label="$1" directory="" output_fd error_fd uptime=""
    shift
    directory="${RECEIPTS}/${label}"
    mkdir -- "${directory}" || return 2
    printf '%q ' "$@" > "${directory}/argv" || return 2
    printf '\n' >> "${directory}/argv" || return 2
    pwd -P > "${directory}/cwd" || return 2
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${directory}/start.utc" || return 2
    read -r uptime _ < /proc/uptime || return 2
    printf '%s\n' "${uptime}" > "${directory}/start.monotonic" || return 2
    exec {output_fd}> "${directory}/stdout" || return 2
    if ! exec {error_fd}> "${directory}/stderr"; then
        exec {output_fd}>&-
        return 2
    fi
    CAPTURE_STATUS=0
    "$@" 1>&"${output_fd}" 2>&"${error_fd}" || CAPTURE_STATUS=$?
    exec {output_fd}>&- {error_fd}>&-
    printf '%d\n' "${CAPTURE_STATUS}" > "${directory}/status" || return 2
    read -r uptime _ < /proc/uptime || return 2
    printf '%s\n' "${uptime}" > "${directory}/end.monotonic" || return 2
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${directory}/end.utc" || return 2
    return 0
}

# The member inventory is independent of the candidate tree and NUL-delimited.
function source_inventory {
    local root="$1" members="$2" path="" kind="" value="" metadata=""
    while IFS= read -r -d '' path; do
        [[ "${path}" != /* && "${path}" != ../* && "${path}" != */../* ]] || return 2
        metadata=$(stat -c '%a %s' -- "${root}/${path}") || return 2
        if [[ -L "${root}/${path}" ]]; then
            kind=symlink
            value=$(readlink -- "${root}/${path}") || return 2
        elif [[ -f "${root}/${path}" ]]; then
            kind='file'
            value=$(sha256sum -- "${root}/${path}") || return 2
            value=${value%% *}
        else
            printf 'Unsupported or missing source: %s\n' "${path}" >&2
            return 2
        fi
        printf '%q\t%s\t%s\t%q\n' "${path}" "${kind}" "${metadata}" "${value}" || return 2
    done < "${members}"
}
