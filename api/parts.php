<?php
// ---------------------------------------------------------------
// Parts Finder API endpoint (drop-in for the existing PHP site).
//
// GET /api/parts.php        -> full catalog as JSON
// GET /api/parts.php?q=pump -> optional server-side filtering
//
// For the demo this reads parts.json. In production, replace the
// load_parts() body with a database query, e.g.:
//
//   $statement = $pdo->query(
//     'SELECT part_number, name, category, supplier, price,
//             stock, replacement FROM parts'
//   );
//   return $statement->fetchAll(PDO::FETCH_ASSOC);
// ---------------------------------------------------------------

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

function load_parts()
{
    $json_path = __DIR__ . '/../parts.json';
    if (!is_readable($json_path)) {
        return null;
    }
    $decoded = json_decode(file_get_contents($json_path), true);
    if (!is_array($decoded) || !isset($decoded['parts'])) {
        return null;
    }
    return $decoded['parts'];
}

function part_matches($part, $query)
{
    $haystack = strtolower(implode(' ', array(
        $part['partNumber'],
        $part['name'],
        $part['category'],
        $part['supplier'],
        implode(' ', $part['keywords']),
        implode(' ', $part['models']),
    )));

    foreach (preg_split('/\s+/', strtolower(trim($query))) as $token) {
        if ($token !== '' && strpos($haystack, $token) !== false) {
            return true;
        }
    }
    return false;
}

$parts = load_parts();
if ($parts === null) {
    http_response_code(500);
    echo json_encode(array('error' => 'Catalog unavailable'));
    exit;
}

$query = isset($_GET['q']) ? trim($_GET['q']) : '';
if ($query !== '') {
    $parts = array_values(array_filter($parts, function ($part) use ($query) {
        return part_matches($part, $query);
    }));
}

echo json_encode(array('parts' => $parts));
