#!/bin/bash
#
# Usage:
#   ./test_similarity.sh Fixtures/Example_Similar.php                           # check a single file
#   ./test_similarity.sh Fixtures/Example_Similar.php Fixtures/Example_Equal.php # check specific files
#   ./test_similarity.sh --verbose Fixtures/Example_Similar.php                  # print similarity scores

VERBOSE=false
if [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
    shift
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [--verbose] <file> [file ...]"
    exit 1
fi

EMBED_API_URL="${EMBED_API_URL:-http://localhost:5000}"
STRUCTURAL_MATCH_THRESHOLD="${STRUCTURAL_MATCH_THRESHOLD:-0.65}"
DEFAULT_THRESHOLD="${DEFAULT_THRESHOLD:-0.85}"

# ── Structural scoring configuration ──────────────────────────────
# Adjustments applied to cosine similarity based on structural signals
# inferred from route attributes and method signatures.
# All values are overridable via environment variables.
#
# PENALTIES (subtracted when structural signals differ)
#
# Target shape: collection (e.g. /users) vs item (e.g. /users/{id})
PENALTY_TARGET_SHAPE="${PENALTY_TARGET_SHAPE:-0.20}"
# Route parameters: one path has {…} placeholders, the other doesn't
PENALTY_ROUTE_PARAMS="${PENALTY_ROUTE_PARAMS:-0.10}"
# HTTP method: disjoint method sets (e.g. GET vs POST)
PENALTY_HTTP_METHOD="${PENALTY_HTTP_METHOD:-0.08}"
# Operation kind: e.g. read-collection vs read-item vs create
# Skipped if either side is "unknown"
PENALTY_OPERATION_KIND="${PENALTY_OPERATION_KIND:-0.15}"
# Path depth difference: per segment difference, capped at PENALTY_PATH_DEPTH_MAX
# Only applied when target shapes differ
PENALTY_PATH_DEPTH_PER_SEG="${PENALTY_PATH_DEPTH_PER_SEG:-0.05}"
PENALTY_PATH_DEPTH_MAX="${PENALTY_PATH_DEPTH_MAX:-0.10}"
# Resource mismatch: first literal path segment differs (e.g. /users vs /subscribers)
# Only applied when both endpoints have an identifiable resource
PENALTY_RESOURCE="${PENALTY_RESOURCE:-0.10}"

if ! curl -sf "$EMBED_API_URL/health" > /dev/null; then
    echo "FAIL: Embed API is not reachable at $EMBED_API_URL"
    exit 1
fi

files=("$@")

# ── Extract metadata once for all files ───────────────────────────
container_paths=()
for file in "${files[@]}"; do
    container_paths+=("/project/$file")
done

metadata_json=$(docker compose run --rm -T php-metadata "${container_paths[@]}" 2>/dev/null) || {
    echo "WARN: metadata extraction failed, penalties disabled" >&2
    metadata_json=""
}

# Helper: get metadata field for a method in a file (container path).
# Returns the raw jq output, or empty string on failure.
get_meta() {
    local container_path="$1"
    local method="$2"
    local field="$3"
    local default="$4"

    if [[ -z "$metadata_json" ]]; then
        echo "$default"
        return
    fi

    local val
    val=$(echo "$metadata_json" | jq -r --arg f "$container_path" --arg m "$method" --arg d "$default" \
        '(.[$f][$m][$ARGS.named.field] // $d)' --arg field "$field" 2>/dev/null)

    if [[ -z "$val" || "$val" == "null" ]]; then
        echo "$default"
    else
        echo "$val"
    fi
}

# Helper: get http_methods as comma-separated string for set intersection.
get_http_methods() {
    local container_path="$1"
    local method="$2"

    if [[ -z "$metadata_json" ]]; then
        echo ""
        return
    fi

    echo "$metadata_json" | jq -r --arg f "$container_path" --arg m "$method" \
        '(.[$f][$m].http_methods // []) | join(",")' 2>/dev/null
}

# Helper: check if two comma-separated method sets have any overlap.
# Returns 0 (true) if overlap exists, 1 (false) if disjoint.
has_method_overlap() {
    local methods_a="$1"
    local methods_b="$2"

    if [[ -z "$methods_a" || -z "$methods_b" ]]; then
        return 0  # no penalty if we can't determine
    fi

    IFS=',' read -ra arr_a <<< "$methods_a"
    IFS=',' read -ra arr_b <<< "$methods_b"

    for a in "${arr_a[@]}"; do
        for b in "${arr_b[@]}"; do
            if [[ "$a" == "$b" ]]; then
                return 0
            fi
        done
    done

    return 1
}

# Check if two methods are a structural match (all key signals align).
# Prints match details to stdout. Returns 0 (true) if all match, 1 (false) otherwise.
is_structural_match() {
    local container_path="$1"
    local method_a="$2"
    local method_b="$3"

    local shape_a shape_b params_a params_b kind_a kind_b methods_a methods_b res_a res_b
    shape_a=$(get_meta "$container_path" "$method_a" "target_shape" "unknown")
    shape_b=$(get_meta "$container_path" "$method_b" "target_shape" "unknown")
    params_a=$(get_meta "$container_path" "$method_a" "has_route_params" "false")
    params_b=$(get_meta "$container_path" "$method_b" "has_route_params" "false")
    kind_a=$(get_meta "$container_path" "$method_a" "operation_kind" "unknown")
    kind_b=$(get_meta "$container_path" "$method_b" "operation_kind" "unknown")
    methods_a=$(get_http_methods "$container_path" "$method_a")
    methods_b=$(get_http_methods "$container_path" "$method_b")
    res_a=$(get_meta "$container_path" "$method_a" "resource" "")
    res_b=$(get_meta "$container_path" "$method_b" "resource" "")

    local mismatches=()

    if [[ "$shape_a" == "unknown" || "$shape_b" == "unknown" ]]; then
        echo "shape=${shape_a}/${shape_b}"
        return 1
    fi
    if [[ "$shape_a" != "$shape_b" ]]; then
        mismatches+=("shape=${shape_a}/${shape_b}")
    fi
    if [[ "$params_a" != "$params_b" ]]; then
        mismatches+=("params=${params_a}/${params_b}")
    fi
    if [[ "$kind_a" != "unknown" && "$kind_b" != "unknown" && "$kind_a" != "$kind_b" ]]; then
        mismatches+=("op=${kind_a}/${kind_b}")
    fi
    if ! has_method_overlap "$methods_a" "$methods_b"; then
        mismatches+=("http=${methods_a}/${methods_b}")
    fi
    if [[ -n "$res_a" && -n "$res_b" && "$res_a" != "$res_b" ]]; then
        mismatches+=("resource=${res_a}/${res_b}")
    fi

    if [[ ${#mismatches[@]} -gt 0 ]]; then
        local mismatch_str
        mismatch_str=$(IFS=','; echo "${mismatches[*]}")
        echo "$mismatch_str"
        return 1
    fi

    # All matched — show the shared signals
    local details="shape=${shape_a},http=${methods_a},op=${kind_a}"
    if [[ -n "$res_a" && -n "$res_b" ]]; then
        details="${details},resource=${res_a}"
    else
        details="${details},resource=?(${res_a:-empty}/${res_b:-empty})"
    fi
    echo "$details"
    return 0
}

# Compute structural adjustment for a pair of methods.
# Returns "adjustment|triggered" where adjustment is negative (penalty).
compute_adjustment() {
    local container_path="$1"
    local method_a="$2"
    local method_b="$3"

    local shape_a shape_b params_a params_b kind_a kind_b depth_a depth_b methods_a methods_b
    shape_a=$(get_meta "$container_path" "$method_a" "target_shape" "unknown")
    shape_b=$(get_meta "$container_path" "$method_b" "target_shape" "unknown")

    # Skip all adjustments if metadata is missing for either method
    if [[ "$shape_a" == "unknown" || "$shape_b" == "unknown" ]]; then
        echo "0|"
        return
    fi

    params_a=$(get_meta "$container_path" "$method_a" "has_route_params" "false")
    params_b=$(get_meta "$container_path" "$method_b" "has_route_params" "false")
    kind_a=$(get_meta "$container_path" "$method_a" "operation_kind" "unknown")
    kind_b=$(get_meta "$container_path" "$method_b" "operation_kind" "unknown")
    depth_a=$(get_meta "$container_path" "$method_a" "path_depth" "0")
    depth_b=$(get_meta "$container_path" "$method_b" "path_depth" "0")
    methods_a=$(get_http_methods "$container_path" "$method_a")
    methods_b=$(get_http_methods "$container_path" "$method_b")

    local adjustment=0
    local triggered=()

    # 1. Target shape
    if [[ "$shape_a" != "$shape_b" ]]; then
        adjustment=$(echo "$adjustment - $PENALTY_TARGET_SHAPE" | bc -l)
        triggered+=("-shape")
    fi

    # 2. Route param presence
    if [[ "$params_a" != "$params_b" ]]; then
        adjustment=$(echo "$adjustment - $PENALTY_ROUTE_PARAMS" | bc -l)
        triggered+=("-params")
    fi

    # 3. HTTP methods
    if ! has_method_overlap "$methods_a" "$methods_b"; then
        adjustment=$(echo "$adjustment - $PENALTY_HTTP_METHOD" | bc -l)
        triggered+=("-http")
    fi

    # 4. Operation kind (skip if either is unknown)
    if [[ "$kind_a" != "unknown" && "$kind_b" != "unknown" ]]; then
        if [[ "$kind_a" != "$kind_b" ]]; then
            adjustment=$(echo "$adjustment - $PENALTY_OPERATION_KIND" | bc -l)
            triggered+=("-operation")
        fi
    fi

    # 5. Resource mismatch (only when both have an identifiable resource)
    local res_a res_b
    res_a=$(get_meta "$container_path" "$method_a" "resource" "")
    res_b=$(get_meta "$container_path" "$method_b" "resource" "")
    if [[ -n "$res_a" && -n "$res_b" && "$res_a" != "$res_b" ]]; then
        adjustment=$(echo "$adjustment - $PENALTY_RESOURCE" | bc -l)
        triggered+=("-resource")
    fi

    # 6. Path depth difference — only when target shapes differ.
    #    Two collections at different depths (e.g. /users vs /users/list)
    #    are exactly the duplicates we want to catch, so no depth penalty.
    if [[ "$shape_a" != "$shape_b" ]]; then
        local depth_diff=$(( depth_a > depth_b ? depth_a - depth_b : depth_b - depth_a ))
        if (( depth_diff > 0 )); then
            local depth_penalty
            depth_penalty=$(echo "$PENALTY_PATH_DEPTH_PER_SEG * $depth_diff" | bc -l)
            if (( $(echo "$depth_penalty > $PENALTY_PATH_DEPTH_MAX" | bc -l) )); then
                depth_penalty="$PENALTY_PATH_DEPTH_MAX"
            fi
            adjustment=$(echo "$adjustment - $depth_penalty" | bc -l)
            triggered+=("-depth")
        fi
    fi

    local triggered_str
    triggered_str=$(IFS=','; echo "${triggered[*]}")
    adjustment=$(echo "$adjustment" | sed 's/^\./0./;s/^-\./-0./')
    echo "${adjustment}|${triggered_str}"
}

validate() {
    local file="$1"
    shift
    local count=$(($# / 2))
    local names=("${@:1:$count}")
    local descriptions=("${@:$((count+1))}")

    local container_path="/project/$file"
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
                # Compute structural adjustment (negative=penalty, positive=bonus)
                local adj_result
                adj_result=$(compute_adjustment "$container_path" "${names[$i]}" "${names[$j]}")
                local adjustment="${adj_result%%|*}"
                local triggered="${adj_result##*|}"

                local adjusted
                adjusted=$(echo "$similarity + $adjustment" | bc -l)
                adjusted=$(echo "$adjusted" | sed 's/^\./0./;s/^-\./-0./')

                # Pick threshold based on structural match
                local threshold match_label match_details
                match_details=$(is_structural_match "$container_path" "${names[$i]}" "${names[$j]}")
                if [[ $? -eq 0 ]]; then
                    threshold="$STRUCTURAL_MATCH_THRESHOLD"
                    match_label="structural-match: ${match_details}"
                else
                    threshold="$DEFAULT_THRESHOLD"
                    match_label="no-structural-match: ${match_details}"
                fi

                local adjust_info=""
                if [[ -n "$triggered" ]]; then
                    adjust_info=" adjust: ${triggered} (${adjustment})"
                fi

                if (( $(echo "$adjusted >= $threshold" | bc -l) )); then
                    if $VERBOSE; then
                        echo "FAIL: ${names[$i]} vs ${names[$j]} sim: ${similarity}${adjust_info} adjusted: ${adjusted} [${match_label}] threshold: ${threshold} in $file"
                    else
                        echo "FAIL: ${names[$i]} vs ${names[$j]} in $file."
                        return 1
                    fi
                    result=1
                elif $VERBOSE; then
                    echo "  OK: ${names[$i]} vs ${names[$j]} sim: ${similarity}${adjust_info} adjusted: ${adjusted} [${match_label}] threshold: ${threshold} in $file"
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
            clean=$(echo "$current" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\+/ /g')
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
