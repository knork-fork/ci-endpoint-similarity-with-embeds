<?php

/**
 * Extracts structural metadata from Symfony controller files using reflection.
 *
 * Accepts one or more PHP file paths as arguments. Outputs JSON to stdout
 * keyed by file path, then method name. Warnings go to stderr.
 *
 * Uses token_get_all() for class discovery and ReflectionAttribute::getArguments()
 * for Route attribute reading (no attribute class instantiation needed).
 */

// --- Autoloader: only stubs known Symfony base classes ---
spl_autoload_register(function ($class) {
    $stubs = [
        'Symfony\\Bundle\\FrameworkBundle\\Controller\\AbstractController' => 'abstract class',
        'Symfony\\Component\\HttpFoundation\\JsonResponse' => 'class',
    ];
    if (isset($stubs[$class])) {
        $parts = explode('\\', $class);
        $name = array_pop($parts);
        $ns = implode('\\', $parts);
        eval("namespace $ns; {$stubs[$class]} $name {}");
    }
});

/**
 * Extract FQCN from a PHP file using token_get_all().
 * Scans for T_NAMESPACE and T_CLASS tokens.
 */
function extractFqcn(string $filePath): ?string
{
    $code = file_get_contents($filePath);
    if ($code === false) {
        return null;
    }

    $tokens = token_get_all($code);
    $namespace = '';
    $className = null;
    $count = count($tokens);

    for ($i = 0; $i < $count; $i++) {
        if (!is_array($tokens[$i])) {
            continue;
        }

        // Extract namespace
        if ($tokens[$i][0] === T_NAMESPACE) {
            $ns = '';
            $i++;
            while ($i < $count) {
                if (is_array($tokens[$i]) && in_array($tokens[$i][0], [T_NAME_QUALIFIED, T_STRING], true)) {
                    $ns .= $tokens[$i][1];
                } elseif (!is_array($tokens[$i]) && ($tokens[$i] === ';' || $tokens[$i] === '{')) {
                    break;
                }
                $i++;
            }
            $namespace = trim($ns);
        }

        // Extract class name (first class declaration only)
        if ($tokens[$i][0] === T_CLASS) {
            // Skip whitespace to find the class name
            $i++;
            while ($i < $count && is_array($tokens[$i]) && $tokens[$i][0] === T_WHITESPACE) {
                $i++;
            }
            if ($i < $count && is_array($tokens[$i]) && $tokens[$i][0] === T_STRING) {
                $className = $tokens[$i][1];
                break;
            }
        }
    }

    if ($className === null) {
        return null;
    }

    return $namespace ? $namespace . '\\' . $className : $className;
}

/**
 * Check if a ReflectionAttribute is a Symfony Route attribute.
 * Matches by short name "Route" or FQCN ending with "\Route".
 */
function isRouteAttribute(ReflectionAttribute $attr): bool
{
    $name = $attr->getName();
    return $name === 'Route' || str_ends_with($name, '\\Route');
}

/**
 * Get the first Route attribute's arguments from a reflection target.
 * Returns null if no Route attribute found.
 * Note: picks the first Route attribute if multiple exist.
 */
function getRouteArgs(ReflectionClass|ReflectionMethod $target): ?array
{
    foreach ($target->getAttributes() as $attr) {
        if (isRouteAttribute($attr)) {
            return $attr->getArguments();
        }
    }
    return null;
}

/**
 * Join class-level route prefix with method-level route path.
 * Normalizes the result: leading /, no trailing / (except root), no double slashes.
 */
function joinAndNormalizePath(string $prefix, string $methodPath): string
{
    $joined = rtrim($prefix, '/') . '/' . ltrim($methodPath, '/');

    // Ensure leading slash
    if ($joined === '' || $joined[0] !== '/') {
        $joined = '/' . $joined;
    }

    // Collapse multiple slashes
    $joined = preg_replace('#/+#', '/', $joined);

    // Remove trailing slash (except root)
    if ($joined !== '/' && str_ends_with($joined, '/')) {
        $joined = rtrim($joined, '/');
    }

    return $joined;
}

/**
 * Split a normalized path into segments, filtering empty strings.
 */
function pathSegments(string $path): array
{
    return array_values(array_filter(explode('/', $path), fn($s) => $s !== ''));
}

/**
 * Extract the primary resource from path segments.
 * Skips common API prefixes and route parameters, returns the first literal segment.
 * Returns empty string if no qualifying segment is found.
 */
function extractResource(array $segments): string
{
    $prefixes = ['api', 'v1', 'v2', 'v3', 'v4'];

    foreach ($segments as $seg) {
        if (preg_match('/^\{[^}]+\}$/', $seg)) {
            continue;
        }
        if (in_array(strtolower($seg), $prefixes, true)) {
            continue;
        }
        if (preg_match('/^\d+$/', $seg)) {
            continue;
        }
        return strtolower($seg);
    }

    return '';
}

/**
 * Determine target shape from path segments.
 * - No segments (root) → "collection"
 * - Last segment is a route parameter ({param}) → "item"
 * - Otherwise → "collection"
 */
function inferTargetShape(array $segments): string
{
    if (empty($segments)) {
        return 'collection';
    }

    $last = end($segments);
    if (preg_match('/^\{[^}]+\}$/', $last)) {
        return 'item';
    }

    return 'collection';
}

/**
 * Derive operation kind from HTTP method and target shape.
 */
function inferOperationKind(string $httpMethod, string $targetShape): string
{
    return match (true) {
        $httpMethod === 'GET' && $targetShape === 'collection' => 'read-collection',
        $httpMethod === 'GET' && $targetShape === 'item' => 'read-item',
        $httpMethod === 'POST' && $targetShape === 'collection' => 'create',
        $httpMethod === 'POST' && $targetShape === 'item' => 'unknown',
        in_array($httpMethod, ['PUT', 'PATCH'], true) && $targetShape === 'item' => 'update-item',
        in_array($httpMethod, ['PUT', 'PATCH'], true) && $targetShape === 'collection' => 'unknown',
        $httpMethod === 'DELETE' && $targetShape === 'item' => 'delete-item',
        $httpMethod === 'DELETE' && $targetShape === 'collection' => 'unknown',
        default => 'unknown',
    };
}

/**
 * Extract HTTP methods from Route attribute arguments.
 * Normalizes to uppercase, deduplicates, sorts.
 * Defaults to ["GET"] if not specified.
 */
function extractHttpMethods(array $routeArgs): array
{
    // methods can be a named argument or positional
    $methods = $routeArgs['methods'] ?? [];

    if (empty($methods)) {
        return ['GET'];
    }

    $methods = array_map('strtoupper', $methods);
    $methods = array_unique($methods);
    sort($methods);

    return array_values($methods);
}

/**
 * Extract the route path from Route attribute arguments.
 * The path can be the first positional argument or the 'path' named argument.
 */
function extractRoutePath(array $routeArgs): string
{
    return $routeArgs[0] ?? $routeArgs['path'] ?? '';
}

// --- Main ---

if ($argc < 2) {
    fwrite(STDERR, "Usage: php extract_metadata.php <file1> [file2] ...\n");
    exit(1);
}

$result = [];

for ($fileIdx = 1; $fileIdx < $argc; $fileIdx++) {
    $filePath = $argv[$fileIdx];

    try {
        $fqcn = extractFqcn($filePath);
        if ($fqcn === null) {
            fwrite(STDERR, "WARN: could not extract class from $filePath\n");
            $result[$filePath] = new stdClass();
            continue;
        }

        require_once $filePath;

        $refClass = new ReflectionClass($fqcn);

        // Class-level route prefix
        $classRouteArgs = getRouteArgs($refClass);
        $classPrefix = $classRouteArgs !== null ? extractRoutePath($classRouteArgs) : '';

        $methods = [];

        foreach ($refClass->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
            // Skip inherited methods
            if ($method->getDeclaringClass()->getName() !== $fqcn) {
                continue;
            }

            $routeArgs = getRouteArgs($method);
            if ($routeArgs === null) {
                continue;
            }

            $methodPath = extractRoutePath($routeArgs);
            $fullRoute = joinAndNormalizePath($classPrefix, $methodPath);
            $segments = pathSegments($fullRoute);
            $hasRouteParams = (bool) preg_match('/\{[^}]+\}/', $fullRoute);
            $targetShape = inferTargetShape($segments);
            $httpMethods = extractHttpMethods($routeArgs);
            $operationKind = inferOperationKind($httpMethods[0], $targetShape);
            $pathDepth = count($segments);

            $resource = extractResource($segments);

            $methods[$method->getName()] = [
                'route' => $fullRoute,
                'target_shape' => $targetShape,
                'has_route_params' => $hasRouteParams,
                'http_methods' => $httpMethods,
                'operation_kind' => $operationKind,
                'path_depth' => $pathDepth,
                'resource' => $resource,
            ];
        }

        // Sort methods by name for deterministic output
        ksort($methods);
        $result[$filePath] = empty($methods) ? new stdClass() : $methods;

    } catch (Throwable $e) {
        fwrite(STDERR, "WARN: extraction failed for $filePath: {$e->getMessage()}\n");
        $result[$filePath] = new stdClass();
    }
}

// Sort by file path for deterministic output
ksort($result);

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
