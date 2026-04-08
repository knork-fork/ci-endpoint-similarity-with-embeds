#!/bin/bash
#
# Usage:
#   ./test_similarity.sh                                                        # check all files in Fixtures/
#   ./test_similarity.sh Fixtures/Example_Similar.php                           # check a single file
#   ./test_similarity.sh Fixtures/Example_Similar.php Fixtures/Example_Equal.php # check specific files
#   ./test_similarity.sh --verbose Fixtures/Example_Similar.php                  # print similarity scores

VERBOSE=false
if [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
    shift
fi

EMBED_API_URL="${EMBED_API_URL:-http://localhost:5000}"
SIMILARITY_THRESHOLD="${SIMILARITY_THRESHOLD:-0.8}"

if ! curl -sf "$EMBED_API_URL/health" > /dev/null; then
    echo "FAIL: Embed API is not reachable at $EMBED_API_URL"
    exit 1
fi

if [[ $# -gt 0 ]]; then
    files=("$@")
else
    FIXTURES_DIR="$(dirname "$0")/Fixtures"
    files=("$FIXTURES_DIR"/*.php)
fi

validate() {
    local file="$1"
    shift
    local count=$(($# / 2))
    local names=("${@:1:$count}")
    local descriptions=("${@:$((count+1))}")

    local result=0

    for ((i=0; i<${#descriptions[@]}; i++)); do
        for ((j=i+1; j<${#descriptions[@]}; j++)); do
            # Failure mode: Two methods have identical descriptions.
            if [[ "${descriptions[$i]}" == "${descriptions[$j]}" ]]; then
                echo "FAIL: ${names[$i]} vs ${names[$j]} have identical descriptions in $file."
                if ! $VERBOSE; then return 1; fi
                result=1
                continue
            fi

            # Failure mode: Two methods have very similar descriptions (e.g., 80%+ similarity).
            similarity=$(curl -sf "$EMBED_API_URL/similarity" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg a "${descriptions[$i]}" --arg b "${descriptions[$j]}" '{a: $a, b: $b}')" \
                | jq -r '.similarity')

            if [[ -n "$similarity" ]]; then
                if (( $(echo "$similarity >= $SIMILARITY_THRESHOLD" | bc -l) )); then
                    echo "FAIL: ${names[$i]} vs ${names[$j]} similar descriptions (${similarity}) in $file."
                    if ! $VERBOSE; then return 1; fi
                    result=1
                elif $VERBOSE; then
                    echo "  OK: ${names[$i]} vs ${names[$j]} similarity: ${similarity} in $file"
                fi
            fi
        done
    done

    return $result
}

for file in "${files[@]}"; do
    # Extract all phpdoc descriptions and their associated method names.
    descriptions=()
    method_names=()
    in_block=false
    current=""
    pending_description=""

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
                pending_description="$clean"
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

        # Match "public function methodName(" to capture the method name
        if [[ -n "$pending_description" && "$trimmed" =~ function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)\( ]]; then
            descriptions+=("$pending_description")
            method_names+=("${BASH_REMATCH[1]}")
            pending_description=""
        fi
    done < "$file"

    if ! validate "$file" "${method_names[@]}" "${descriptions[@]}"; then
        exit 1
    fi
done

echo "OK"
