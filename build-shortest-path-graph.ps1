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

function nodeToString($node) { 
    $nodeTrain = if ($node.hasTrainArrived) { " train arrived" } else {""}
    return "[$($node.line)] $($node.station) to $($node.direction)$nodeTrain"
}

function addEdge ($sourceNode, $targetNode, $time) {
    #Write-Host  (nodeToString $sourceNode) -> (nodeToString $targetNode): $time minutes
    $shortestTimesGraph.edges += @{source= $sourceNode; target= $targetNode; time= $time }
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

getShortestPath "[M1] Mihai Bravu to Dristor 1" "[M1] Obor to Ștefan cel Mare train arrived"