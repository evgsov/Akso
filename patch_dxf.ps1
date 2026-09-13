$content = Get-Content lib/data/dxf/dxf_writer.dart -Raw

$content = $content -replace "'  0\\nLAYER\\n  2\\n$name", "'  0\nLAYER\n  2\n$($_toAutoCadString(name))"
$content = $content -replace "'  0\\nLINE\\n  8\\n$layer", "'  0\nLINE\n  8\n$($_toAutoCadString(layer))"
$content = $content -replace "'  0\\nTEXT\\n  8\\n$layer", "'  0\nTEXT\n  8\n$($_toAutoCadString(layer))"
$content = $content -replace "'  1\\n$text", "'  1\n$($_toAutoCadString(text))"
$content = $content -replace "'  0\\nCIRCLE\\n  8\\n$layer", "'  0\nCIRCLE\n  8\n$($_toAutoCadString(layer))"

$content | Set-Content -Encoding utf8 lib/data/dxf/dxf_writer.dart
