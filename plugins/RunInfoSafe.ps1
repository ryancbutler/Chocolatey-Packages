# PS7-safe replacement for AU's built-in RunInfo plugin.
#
# The stock plugin deep-clones $Info.Options with BinaryFormatter, which is
# disabled by default in .NET 8 and removed in .NET 9, so it throws under pwsh.
# It also can't serialize ScriptBlocks (we pass a BeforeEach block).
#
# This version clones only the dictionary spine, which is all the redaction
# below actually mutates. Leaf values are shared by reference and never touched.
#
# Registered under a non-stock name because AU resolves built-in plugins before
# $Options.PluginPath, so a file named RunInfo.ps1 here would be ignored.

param(
    $Info,

    # Path to XML file to save
    [string] $Path = 'update_info.xml',

    # Match options with those words to erase
    [string[]] $Exclude = @('password', 'apikey')
)

function clone_spine($Value) {
    if ($Value -is [System.Collections.Specialized.OrderedDictionary]) {
        $copy = [ordered]@{}
        foreach ($k in @($Value.Keys)) { $copy[$k] = clone_spine $Value[$k] }
        return $copy
    }
    if ($Value -is [hashtable]) {
        $copy = @{}
        foreach ($k in @($Value.Keys)) { $copy[$k] = clone_spine $Value[$k] }
        return $copy
    }
    return $Value
}

function result($msg) { $Info.plugin_results.RunInfoSafe += $msg; Write-Host $msg }

$Info.plugin_results.RunInfoSafe = @()
$format = '{0,-15}{1}'

$orig_opts = $Info.Options
$opts      = clone_spine $orig_opts
$excluded  = ''

foreach ($w in $Exclude) {
    foreach ($key in @($opts.Keys)) {
        $section = $opts.$key
        if ($section -isnot [hashtable] -and $section -isnot [System.Collections.Specialized.OrderedDictionary]) { continue }
        foreach ($subkey in @($section.Keys)) {
            if ($subkey -like "*$w*") {
                $excluded += "$key.$subkey "
                $section.$subkey = '*****'
            }
        }
    }
}

if ($excluded) { result ($format -f 'Excluded:', $excluded) }
result ($format -f 'File:', $Path)

$Info.Options = $opts
try {
    $Info | Export-CliXml $Path
}
finally {
    $Info.Options = $orig_opts
}
