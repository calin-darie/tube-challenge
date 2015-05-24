$stationsFile = if ($args[0]) {$args[0]} else { join-path $PSScriptRoot "stations.json"}

$stationsAsJson = (Get-Content $stationsFile) -join "`n"

$stations = ConvertFrom-Json $stationsAsJson

$shortestTimesGraph = @{ nodes = @() }

foreach ($line in $stations) {
    for ($i = 0; $i -lt $line.stations.Length; $i ++) {
        $station = $line.stations[$i]
        if ($i - 1 -ge 0) {
            $shortestTimesGraph.nodes += @{ 
                "station" = $station;
                "line" = $line.name;
                "direction" = $line.stations[$i-1];
                hasTrainArrived = $false
            }
            $shortestTimesGraph.nodes += @{ 
                "station" = $station;
                "line" = $line.name;
                "direction" = $line.stations[$i-1];
                hasTrainArrived = $true
            }
        }
        if ($i + 1 -lt $line.stations.Length) {
            $shortestTimesGraph.nodes += @{ 
                "station" = $station;
                "line" = $line.name;
                "direction" = $line.stations[$i+1];
                hasTrainArrived = $false
            }
            $shortestTimesGraph.nodes += @{ 
                "station" = $station;
                "line" = $line.name;
                "direction" = $line.stations[$i+1];
                hasTrainArrived = $true
            }
        }
    }
}

$shortestTimesGraph.nodes