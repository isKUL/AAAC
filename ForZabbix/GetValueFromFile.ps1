param(
    [string]$stringPath,
    [string]$stringDelimiter,
    [string]$stringKey
)
if (Test-Path -Path $stringPath)
{
    foreach ($line in get-content $stringPath)
    {
        if ($line -match $stringKey+$stringDelimiter)
        {
            write-host $line.split($stringDelimiter)[1];
            break;
        }
    }
}