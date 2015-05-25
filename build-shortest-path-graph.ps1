function readFromJsonFile ($file) {
    $json = (Get-Content $file) -join "`n"
    $result = ConvertFrom-Json $json
    return $result
}

$lines = readFromJsonFile (join-path $PSScriptRoot "stations.json")
$times = readFromJsonFile (join-path $PSScriptRoot "times.json")
$shortestTimesGraph = @{ nodes = @{}; edges = @() }

function  addNodes ($nodes) {
    if ($nodes -eq $null -or $nodes.Length -eq 0) { return }
    $nodesOfTheSameStation = $shortestTimesGraph.nodes[$nodes[0].station];
    if (-not $nodesOfTheSameStation) {
        $nodesOfTheSameStation = @()
    }
    $nodesOfTheSameStation += $nodes 
    $shortestTimesGraph.nodes[$nodes[0].station] = $nodesOfTheSameStation
}

function getAverageWaitingTime ($lineName) {
    return ($times.waitingTimes | Where { $_.line -eq $lineName } | Select -First 1).time / 2
}

function getRideTime ($station1, $station2) {
    return 2;
}

function getNode () {
    Param ($line, $stationIndex, $direction, $hasTrainArrived)
    $station = $line.stations[$stationIndex]
    return @{
        station = $station; 
        line = $line.name; 
        direction = $line.stations[$stationIndex+$direction]; 
        hasTrainArrived = $hasTrainArrived;
    }
}

function addEdge ($node1, $node2, $weight) {
    $node1Train = if ($node1.hasTrainArrived) { "train arrived" } else {""}
    $node2Train = if ($node2.hasTrainArrived) { "train arrived" } else {""}
    Write-Host [ $node1.line ] $node1.station $node1Train -> $node2.station $node2Train :  $weight minutes
    $shortestTimesGraph.edges += @{source= $node1; destination= $node2 }
}

foreach ($line in $lines) {
    for ($i = 0; $i -lt $line.stations.Length; $i ++) {
        if ($i - 1 -ge 0) {
            addNodes @(
                (getNode $line $i -direction -1 -hasTrainArrived $false),
                (getNode $line $i -direction -1 -hasTrainArrived $true)
            )
        }
        if ($i + 1 -lt $line.stations.Length) {
            addNodes @(
                (getNode $line $i -direction +1 -hasTrainArrived $false),
                (getNode $line $i -direction +1 -hasTrainArrived $true)
            )
        }
    }
}

foreach ($line in $lines) {
    for ($i = 0; $i -lt $line.stations.Length; $i ++) {
        addEdge `
            (getNode $line $i -direction +1 -hasTrainArrived $false) `
            (getNode $line $i -direction +1 -hasTrainArrived $true) `
            (getAverageWaitingTime $line.name)
        
        if ($i -eq $line.stations.Length - 1) { break }

        $isNextStationEndOfLine = $i + 1 -eq $line.stations.Length - 1
        $directionFromNextStation = if ($isNextStationEndOfLine) {-1} else {+1}

        addEdge `
            (getNode $line $i   -direction +1 -hasTrainArrived $true) `
            (getNode $line ($i+1) -direction $directionFromNextStation -hasTrainArrived $true) `
            (getRideTime $line.stations[$i] $line.stations[$i+1])
        

        $isThisStationEndOfLine = $i -eq 0
        $directionFromHere = if ($isThisStationEndOfLine) {+1} else {-1}
        
        addEdge `
            (getNode $line ($i+1) -direction -1 -hasTrainArrived $true) `
            (getNode $line $i -direction $directionFromHere -hasTrainArrived $true) `
            (getRideTime $line.stations[$i] $line.stations[$i+1])
    }
}

foreach ($walkingTime in $times.walkingTimes) {
    $nodes1 = $shortestTimesGraph.nodes[$walkingTime.station1]
    $nodes2 = $shortestTimesGraph.nodes[$walkingTime.station2]
    foreach ($node1 in $nodes1) {
        foreach ($node2 in $nodes2) {
            if (-not $node2.hasTrainArrived) { addEdge $node1 $node2 $walkingTime.time }
            if (-not $node1.hasTrainArrived) { addEdge $node2 $node1 $walkingTime.time }
        }
    }
}

foreach ($stationEntry in $shortestTimesGraph.nodes.GetEnumerator()) {
    foreach ($node1 in $stationEntry.Value) {
        foreach ($node2 in $stationEntry.Value) {
            if ($node1.line -eq $node2.line) {continue}
            if (-not $node2.hasTrainArrived) { addEdge $node1 $node2 (getAverageWaitingTime $node2.line) }
            if (-not $node1.hasTrainArrived) { addEdge $node2 $node1 (getAverageWaitingTime $node1.line) }
        }
    }
}