#!/bin/bash
#
# Usage:
#   ./test_similarity.sh                                                        # check all files in Fixtures/
#   ./test_similarity.sh Fixtures/Example_Similar.php                           # check a single file
#   ./test_similarity.sh Fixtures/Example_Similar.php Fixtures/Example_Equal.php # check specific files

exit_code=0

if [[ $# -gt 0 ]]; then
    files=("$@")
else
    FIXTURES_DIR="$(dirname "$0")/Fixtures"
    files=("$FIXTURES_DIR"/*.php)
fi

validate() {
    local file="$1"
    shift
    local descriptions=("$@")

    for ((i=0; i<${#descriptions[@]}; i++)); do
        for ((j=i+1; j<${#descriptions[@]}; j++)); do
            # Failure mode: Two methods have identical descriptions.
            if [[ "${descriptions[$i]}" == "${descriptions[$j]}" ]]; then
                echo "FAIL: Methods have identical descriptions in $file."
                return 1
            fi
        done
    done

    return 0
}

for file in "${files[@]}"; do
    # Extract all phpdoc descriptions: content between /** and */ lines,
    # stripping leading * and collapsing into single-line strings.
    descriptions=()
    in_block=false
    current=""

    while IFS= read -r line; do
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

        if [[ "$trimmed" == "/**" ]]; then
            in_block=true
            current=""
            continue
        fi

        if [[ "$trimmed" == "*/" ]]; then
            in_block=false
            # Collapse whitespace into a single clean line
            clean=$(echo "$current" | xargs)
            if [[ -n "$clean" ]]; then
                descriptions+=("$clean")
            fi
            continue
        fi

        if $in_block; then
            # Strip leading "* " or "*" prefix
            content=$(echo "$trimmed" | sed 's/^\* \?//')
            if [[ -n "$content" ]]; then
                current="$current $content"
            fi
        fi
    done < "$file"

    if ! validate "$file" "${descriptions[@]}"; then
        exit 1
    fi
done

echo "OK"
