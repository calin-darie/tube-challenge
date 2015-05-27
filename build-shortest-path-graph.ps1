param(
    [string] $linesJsonPath = (join-path $PSScriptRoot "stations.json"),
    [string] $timesJsonPath = (join-path $PSScriptRoot "times.json")
)

# ===================================
# loading data
# ===================================

function readFromJsonFile ($file) {
    $json = (Get-Content $file) -join "`n"
    $result = ConvertFrom-Json $json
    return $result
}

$lines = readFromJsonFile $linesJsonPath
$times = readFromJsonFile $timesJsonPath
$shortestTimesGraph = @{ nodes = @{}; edges = @() }



# ===================================
# building the graph
# ===================================

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

function buildNodes () {
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
}

function buildWaitingEdges() {
    foreach ($stationEntry in $shortestTimesGraph.nodes.GetEnumerator()) {
        foreach ($node in $stationEntry.Value) {
            if (-not $node.hasTrainArrived) {
                $target = $node.Clone()
                $target.hasTrainArrived = $true
                addEdge $node $target (getAverageWaitingTime $node.line)
            }
        }
    }
}

function buildRideEdges() {
    foreach ($line in $lines) {
        for ($i = 0; $i -lt $line.stations.Length; $i ++) {
            addEdge `
                (getNode $line $i -direction +1 -hasTrainArrived $false) `
                (getNode $line $i -direction +1 -hasTrainArrived $true) `
                (getAverageWaitingTime $line.name)
        
            if ($i -eq $line.stations.Length - 1) { break }

            $isNextStationEndOfLine = $i + 1 -eq $line.stations.Length - 1
            if ($isNextStationEndOfLine) {
                addEdge `
                    (getNode $line $i   -direction +1 -hasTrainArrived $true) `
                    (getNode $line ($i+1) -direction -1 -hasTrainArrived $false) `
                    (getRideTime $line.stations[$i] $line.stations[$i+1])
            } else {
                addEdge `
                    (getNode $line $i   -direction +1 -hasTrainArrived $true) `
                    (getNode $line ($i+1) -direction +1 -hasTrainArrived $true) `
                    (getRideTime $line.stations[$i] $line.stations[$i+1])
            }
        

            $isThisStationEndOfLine = $i -eq 0
            if ($isThisStationEndOfLine) {
                addEdge `
                    (getNode $line ($i+1) -direction -1 -hasTrainArrived $true) `
                    (getNode $line $i -direction +1 -hasTrainArrived $false) `
                    (getRideTime $line.stations[$i] $line.stations[$i+1])
            } else {
                addEdge `
                    (getNode $line ($i+1) -direction -1 -hasTrainArrived $true) `
                    (getNode $line $i -direction -1 -hasTrainArrived $true) `
                    (getRideTime $line.stations[$i] $line.stations[$i+1])
            }
        }
    }
}

function buildWalkingEdges () {
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
}

function buildSamePlatformTransferEdges () {
    foreach ($stationEntry in $shortestTimesGraph.nodes.GetEnumerator()) {
        foreach ($node1 in $stationEntry.Value) {
            foreach ($node2 in $stationEntry.Value) {
                if (-not $node2.hasTrainArrived) { addEdge $node1 $node2 (getSamePlatformTransferTime $stationEntry.Key) }
                if (-not $node1.hasTrainArrived) { addEdge $node2 $node1 (getSamePlatformTransferTime $stationEntry.Key) }
            }
        }
    }
}


buildNodes
buildWaitingEdges
buildRideEdges
buildWalkingEdges
buildSamePlatformTransferEdges



# ===================================
# importing and wrapping quickGraph
# ===================================


$quickGraphDll = Get-ChildItem QuickGraph.dll -Recurse | Select -First 1
if ($quickGraphDll -eq $null) {
    $nuget = Join-Path $PSScriptRoot "nuget.exe"
    if (-not (Test-Path $nuget)) { 
        Write-Host downloading nuget...
        Invoke-WebRequest "https://nuget.org/nuget.exe" -OutFile $nuget 
    }
    .\nuget install quickgraph
}
Add-Type -Path $quickGraphDll.FullName

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


function getShortestPathThrough($stations) {
    $path = @{ edges = @(); time = 0}
    $isFirstStation = $true
    $targetNode = $null
    foreach ($station in $stations) {
        $sourceNode = $targetNode

        $targetNode = $shortestTimesGraph.nodes[$station] | Where-Object {$_.hasTrainArrived -eq (-not $isFirstStation)} | Select -First 1
        if ($sourceNode -ne $null) { 
            $path.edges += getShortestPath (nodeToString $sourceNode) (nodeToString $targetNode) 
        }
        
        $isFirstStation = $false
    }
    $minutes = ($path.edges | foreach {$timeMap[$_]} | Measure-Object -Sum).Sum
    $path.time = [System.TimeSpan]::FromMinutes($minutes)
    return $path
}


# ===================================
# testing
# ===================================

Write-Host Testing...
$path = getShortestPath "[M2] Unirii 2 to Universitate" "[M2] Unirii 2 to Universitate train arrived"
Write-Host Waiting for train is modeled by edge.
if ($path.Count -ne 1) { Write-Error "Failed" } else { Write-Host "Passed"}

$path = getShortestPath "[M1] Obor to Ștefan cel Mare" "[M1] Obor to Iancului"
Write-Host When I start by waiting for the wrong direction, I can change my mind.
if ($path.Count -ne 1) { Write-Error "Failed" } else { Write-Host "Passed"}

$path = getShortestPath "[M1] Dristor 1 to Mihai Bravu" "[M1] Dristor 2 to Muncii"
Write-Host When I want to reach a station I can walk to, I will walk.
if ($path.Count -ne 1) { Write-Error "Failed" } else { Write-Host "Passed"}

$path = getShortestPath "[M3] Nicolae Teclu to Anghel Saligny train arrived" "[M3] Anghel Saligny to Nicolae Teclu train arrived"
Write-Host When switching directions at the end of the line, I have to wait.
if ($path.Count -eq 1) { Write-Error "Failed" } else { Write-Host "Passed"}



# ===================================
# trying out checkpoint permutations
# ===================================

function permutations ($array) {
    if ($array.Count -le 1) {return @($array)}

    $result = New-Object "System.Collections.Generic.List[object[]]"
    for ($i = 0; $i -lt $array.Count; $i++) {
        $reducedProblemArray = 0..($array.Count-1) | Where-Object {$_ -ne $i} | foreach { $array[$_] }
        permutations $reducedProblemArray | foreach { $result.Add(@($array[$i]) + $_) }
    }
    return $result
}

Write-Host Trying out checkpoint permutations...
$checkpointSequences = permutations ("Preciziei", "Parc Bazilescu", "Gara de Nord 2", "Obor", "Dristor 2") | `
    foreach { @{stations = $_ }}
foreach ($checkpointSequence in $checkpointSequences) {
    $completeCheckpointSequence = @("Depoul Pantelimon", "Anghel Saligny") + $checkpointSequence.stations + @("Pipera", "Berceni")
    $path = getShortestPathThrough $completeCheckpointSequence
    $missingStations = @()
    foreach ($station in $shortestTimesGraph.nodes.Keys) {
        $found = $false
        foreach ($edge in $path.edges) {
            if ($edge.source.contains("$station to") -or $edge.target.contains("$station to")) {
                $found = $true;
                break
            }
        }
        if (-not $found) { $missingStations += $station }
    }
    if ($missingStations.Count -gt 0) { 
        $path.time = $path.time.Add([System.TimeSpan]::FromMinutes(6 + 2 * $missingStations.Count))
    }
    $checkpointSequence.completeSequence = $completeCheckpointSequence
    $checkpointSequence.missingStations = $missingStations
    $checkpointSequence.time = $path.time
}

$checkpointSequences | Sort-Object {$_.time} -descending | Select -Last 50 | foreach {
    Write-Host =================================
    Write-Host $_.time
    Write-Host ($_.completeSequence -join " ")
    if ($_.missingStations.Count -gt 0) { 
        Write-Host ! missing stations: 
        $_.missingStations | Write-Host
    }
}


#debug queries:
#$graph.Edges | Where-Object {$_.source.Contains('Unirii 2 to')}
#getShortestPathThrough @("Depoul Pantelimon", "Anghel Saligny", "Preciziei", 'Parc Bazilescu', "Gara de Nord 2", 'Dristor 2', 'Pipera', 'Berceni')
