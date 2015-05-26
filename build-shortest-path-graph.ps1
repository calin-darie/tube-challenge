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

function getSamePlatformTransferTime ($station) {
    return 0.5;
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

function nodeToString($node) { 
    $nodeTrain = if ($node.hasTrainArrived) { " train arrived" } else {""}
    return "[$($node.line)] $($node.station) to $($node.direction)$nodeTrain"
}

function edgeToString ($edge) {
    return "$(nodeToString $edge.source) -> $(nodeToString $edge.target): $($edge.time) minutes"
}

function addEdge ($sourceNode, $targetNode, $time) {
    $newEdge = @{source= $sourceNode; target= $targetNode; time= $time }
    $shortestTimesGraph.edges += $newEdge
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
            if (-not $node2.hasTrainArrived) { addEdge $node1 $node2 (getSamePlatformTransferTime $stationEntry.Key) }
            if (-not $node1.hasTrainArrived) { addEdge $node2 $node1 (getSamePlatformTransferTime $stationEntry.Key) }
        }
    }
}

foreach ($stationEntry in $shortestTimesGraph.nodes.GetEnumerator()) {
    foreach ($node in $stationEntry.Value) {
        if (-not $node.hasTrainArrived) {
            $target = $node.Clone()
            $target.hasTrainArrived = $true
            addEdge $node $target (getAverageWaitingTime $node.line)
        }
    }
}

$nuget = Join-Path $PSScriptRoot "nuget.exe"
if (-not (Test-Path $nuget)) { 
    Write-Host downloading nuget...
    Invoke-WebRequest "https://nuget.org/nuget.exe" -OutFile $nuget 
}
.\nuget install quickgraph
$quickGraph = (Get-ChildItem QuickGraph.dll -Recurse | Select -First 1).FullName
Add-Type -Path $quickGraph

$graph = New-Object "QuickGraph.AdjacencyGraph[string, QuickGraph.Edge[string]]"
$timeMap = New-Object "system.collections.generic.dictionary[QuickGraph.Edge[string], double]"
foreach ($edge in $shortestTimesGraph.edges) {
    $quickGraphEdge = New-Object "QuickGraph.Edge[string]" `
        -ArgumentList @((nodeToString $edge.source), (nodeToString $edge.target))
    [void]$graph.AddVerticesAndEdge($quickGraphEdge)
    $timeMap.Add($quickGraphEdge, $edge.time)
}

function getShortestPath($source, $destination) {
    $quickGraphWeightIndexer = [QuickGraph.Algorithms.AlgorithmExtensions]::GetIndexer($timeMap)
    $tryGetPathFunc = [QuickGraph.Algorithms.AlgorithmExtensions]::ShortestPathsDijkstra( `
        [QuickGraph.IVertexAndEdgeListGraph[string, QuickGraph.Edge[string]]]$graph, `
        [Func[QuickGraph.Edge[string], double]]$quickGraphWeightIndexer, `
        [string]$source)
    $path = $null
    $success = $tryGetPathFunc.Invoke($destination, [ref]$path)
    return $path
}

#debug queries:
#$graph.Edges | Where-Object {$_.source.Contains('Unirii 2 to')}

$path = getShortestPath "[M2] Unirii 2 to Universitate" "[M2] Unirii 2 to Universitate train arrived"
if ($path.Count -ne 1) { Write-Error "[Failed] Waiting for train is modeled by edge." }

$path = getShortestPath "[M1] Obor to Ștefan cel Mare" "[M1] Obor to Iancului"
if ($path.Count -ne 1) { Write-Error "[Failed] When I start by waiting for the wrong direction, I can change my mind." }

$path = getShortestPath "[M1] Dristor 1 to Mihai Bravu" "[M1] Dristor 2 to Muncii"
if ($path.Count -ne 1) { Write-Error "[Failed] When I want to reach a station I can walk to, I will walk." }


$path = getShortestPath "[M1] Timpuri Noi to Mihai Bravu" "[M1] Victoriei 1 to Gara de Nord 1"
$time = $path | foreach {$timeMap[$_]} | Measure-Object -Sum
$path
Write-Host $time.Sum minutes
