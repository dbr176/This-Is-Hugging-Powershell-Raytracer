using module Communary.ConsoleExtensions

$Right = [System.Numerics.Vector3]::UnitX
$Forward = [System.Numerics.Vector3]::UnitZ
$Up = [System.Numerics.Vector3]::UnitY
$Zero = [System.Numerics.Vector3]::Zero

class Int3 {
    [int]$X
    [int]$Y
    [int]$Z

    Int3(
        [int]$X,
        [int]$Y,
        [int]$z
    ) {
        $this.X = $X
        $this.Y = $Y
        $this.Z = $Z
    }
}

class Ray {
    [System.Numerics.Vector3]$Direction
    [System.Numerics.Vector3]$Origin
}

class ColoredRay {
    [Ray]$Ray
    [System.Numerics.Vector3]$Color
}

class Camera {
    [System.Numerics.Vector3]$Position
    [System.Numerics.Vector3]$Fwd
    [System.Numerics.Vector3]$Right
    [System.Numerics.Vector3]$Up

    [float]$Width
    [float]$Height

    [Ray]GetRay([int]$x, [int]$y) {
        $nx = ($x / $this.Width * 0.5) * 2.0 * $this.Right
        $ny = -($y / $this.Height * 0.5) * 2.0 * $this.Up

        $ray = [Ray]::new()
        $ray.Direction = [System.Numerics.Vector3]::Normalize(
            ($nx + $ny + $this.Fwd) - $this.Position)
        $ray.Origin = $this.Position

        return $ray
    }
}

class Tri {
    [System.Numerics.Vector3]$A
    [System.Numerics.Vector3]$B
    [System.Numerics.Vector3]$C
    Tri(
        [System.Numerics.Vector3]$A,
        [System.Numerics.Vector3]$B,
        [System.Numerics.Vector3]$C
    ) {
        $this.A = $A
        $this.B = $B
        $this.C = $C
    }

    [System.Numerics.Vector3]GetNormal() {
        $e1 = $this.B - $this.A
        $e2 = $this.C - $this.A

        return [System.Numerics.Vector3]::Normalize($e1 * $e2)
    }
}

class Mesh {
    [System.Numerics.Vector3[]]$Points
    [Int3[]]$Faces

    [void]AddTri([int]$a, [int]$b, [int]$c) {
        $this.Faces += [Int3]::new($a, $b, $c) # += -> Add
    }

    [void]AddQuad([int]$a, [int]$b, [int]$c, [int]$d) {
        $this.AddTri($d, $a, $b)
        $this.AddTri($b, $c, $d)
    }

    [void]Translate([System.Numerics.Vector3]$direction) {
        for($i = 0; $i -lt $this.Points.Count; $i++) {
            $this.Points[$i] += $direction
        }
    }

    [void]Translate([float]$x, [float]$y, [float]$z) {
        $direction = [System.Numerics.Vector3]::new($x, $y, $z)
        $this.Translate($direction)
    }
}

function Get-FromToRay([System.Numerics.Vector3]$from, [System.Numerics.Vector3]$to) {
    $ray = [Ray]::new()
    $ray.Origin = $from
    $ray.Direction = [System.Numerics.Vector3]::Normalize($to - $from)
    return $ray
}

function New-Cube {
    $mesh = [Mesh]::new()

    $upRight = $Up + $Right
    $upFwd = $Up + $Forward
    $upFwdRight = $Up + $Forward + $Right
    $rightFwd = $Right + $Forward

    $points = @($Zero, $Up, $upRight, $upFwd, $upFwdRight, $Right, $rightFwd, $Forward)

    $mesh.AddQuad(0, 5, 2, 1)
    $mesh.AddQuad(0, 1, 3, 7)
    $mesh.AddQuad(0, 7, 6, 5)
    $mesh.AddQuad(5, 6, 4, 2)
    $mesh.AddQuad(7, 3, 4, 6)
    $mesh.AddQuad(4, 3, 1, 2)
    
    $mesh.Points = $points
    return $mesh
}

function MeshToTraingles([Mesh]$mesh) {
    $result = New-Object Tri[] $mesh.Faces.Length
    $faces = $mesh.Faces
    $points = $mesh.Points
    $i = 0

    $faces | foreach {
        $tri = 
            [Tri]::new(
                $points[$_.X],
                $points[$_.Y],
                $points[$_.Z])
        $result[$i] = $tri
        $i++
    }
    return $result
}

function BarTest([Ray]$ray, [System.Numerics.Vector3]$v1, [System.Numerics.Vector3]$v2, [System.Numerics.Vector3]$v3) {
    $epsilon = 0.00000001

    $d = $ray.Direction
    $e1 = $v2 - $v1
    $e2 = $v3 - $v1

    $p = [System.Numerics.Vector3]::Cross($d, $e2)
    $det = [System.Numerics.Vector3]::Dot($e1, $p)

    if([System.Math]::Abs($det) -lt $epsilon) {
        return $null
    }

    $invDet = 1.0 / $det
    $t = $ray.Origin - $v1
    $u = [System.Numerics.Vector3]::Dot($t, $p) * $invDet

    if($u -lt 0.0 -or $u -gt 1.0) {
        return $null
    }

    $q = [System.Numerics.Vector3]::Cross($t, $e1)
    $v = [System.Numerics.Vector3]::Dot($d, $q) * $invDet

    if($v -lt 0 -or $u + $v -gt 1.0) {
        return $null
    }

    $nt = [System.Numerics.Vector3]::Dot($e2, $q) * $invDet

    if($nt -gt $epsilon) {
        return $nt * $ray.Direction + $ray.Origin
    }

    return $null
}

function BarTestTri([Ray]$ray, [Tri]$tri) {
    return BarTest -ray $ray -v1 $tri.A -v2 $tri.B -v3 $tri.C
}

function ShadowRay(
    [System.Numerics.Vector3]$p,
    [Tri[]]$triangles,
    [System.Numerics.Vector3]$lightPositions
) {
    $intencity = 0.0

    $lightPositions | foreach {
        $seeLight = $true
        $light = $_
        $ray = Get-FromToRay $p $light

        $triangles | where { $seeLight } | foreach {
            $tri = $_
            $test = BarTestTri $ray $tri

            if($test -eq $null) {
                $intencity += 0.1
                $seeLight = $false
            }
        }
        if($seeLight) {
            $intencity += 0.1
        }
    }
    return $intencity
}

function RayTracer($depth, $width, $height, [Ray[,]]$rays, $tris) {
    $result = New-Object 'System.Numerics.Vector3[,]' $width, $height

    $lightPos = [System.Numerics.Vector3]::new(-1, 0, 10)

    $totalIters = $width * $height
    $iter = 0

    for($x = 0; $x -lt $width; $x++) {
        for($y = 0; $y -lt $height; $y++) {
            
            $ray = $rays[$x, $y]
            $result[$x, $y] = [System.Numerics.Vector3]::Zero

            $hitPoints = New-Object 'System.Numerics.Vector3[]' $depth
            $normals = New-Object 'System.Numerics.Vector3[]' $depth
            $distances = New-Object 'float[]' $depth
            $materialColor = New-Object 'System.Numerics.Vector3[]' $depth
            $shadowColors = New-Object 'System.Numerics.Vector3[]' $depth

            $hits = 0
            $hit = $false

            for($d = 0; $d -lt $depth; $d++) {
                $hit = $false
                $distances[$d] = 100000000000

                for($triIdx = 0; $triIdx -lt $tris.Length; $triIdx++) {
                    $tri = $tris[$triIdx]
                    $hitPoint = BarTestTri $ray $tri

                    if($hitPoint -ne $null) {
                        $e1 = $tri.C - $tri.A
                        $e2 = $tri.C - $tri.B

                        $normal = [System.Numerics.Vector3]::Normalize([System.Numerics.Vector3]::Cross($e1, $e2))
                        $dist = [System.Numerics.Vector3]::Dot($ray.Origin - $hitPoint,$ray.Origin - $hitPoint)

                        $hitPoint -= 0.0001 * $normal

                        if ($distances[$d] -gt $dist) {
                            $hit = $true
                            $hitPoints[$d] = $hitPoint
                            $distances[$d] = $dist
                            $normals[$d] = $normal
                            $materialColor[$d] = [System.Numerics.Vector3]::new(0.1, 0.5, 0.5)
                        }
                    }
                }

                if (-not $hit) { break }
                $hits++

                $ray.Origin = $hitPoints[$d]
                $ray.Direction = [System.Numerics.Vector3]::Reflect($ray.Direction, $normals[$d])
            }

            for($hitIdx = $hits - 1; $hitIdx -ge 0; $hitIdx--) {
                $toLight = $lightPos - $hitPoints[$hitIdx]
                $shadowRay = [Ray]::new()
                $shadowRay.Direction = $toLight
                $shadowRay.Origin = $hitPoints[$hitIdx]

                $hit = $false

                for($triIdx = 0; $triIdx -lt $tris.Length; $triIdx++) {
                    $tri = $tris[$triIdx]
                    $hitPoint = BarTestTri $shadowRay $tri

                    if ($hitPoint -ne $null) {
                        $dist = [System.Numerics.Vector3]::Dot($shadowRay.Origin - $hitPoint, $shadowRay.Origin - $hitPoint)
                        $hit = $true
                        break
                    }
                }

                if (-not $hit) {
                    $dist = 3 / [Math]::Sqrt([System.Numerics.Vector3]::Dot($lightPos - $hitPoints[$hitIdx], $lightPos - $hitPoints[$hitIdx]))
                    $distVec = [System.Numerics.Vector3]::new($dist, $dist, $dist)
                    $ambientVec = [System.Numerics.Vector3]::new(0.1, 0.1, 0.1)
                    $shadowColors[$hitIdx] = ($distVec + $ambientVec) / ($hitIdx + 1)
                }
                else {
                    $shadowColors[$hitIdx] = $Zero
                }
            }

            for($hitIdx = $hits - 1; $hitIdx -ge 0; $hitIdx--) {
                $result[$x, $y] += $materialColor[$hitIdx] * $shadowColors[$hitIdx]
            }

            # $iter++
            # $I = $iter * 100 / $totalIters
            # Write-Progress -Activity "Rendering in progress" -Status "$I% Complete:" -PercentComplete $I;
            $color = Convert-VectorToRgb $result[$x, $y]
            Write-RGB -Text "  " -BackgroundColor $color -NoNewLine
        }
        Write-RGB -Text ' '
    }
    return ,$result
}
function Convert-VectorToRgb([System.Numerics.Vector3]$vec) {
    $R = $vec.X * 255
    $G = $vec.Y * 255
    $B = $vec.Z * 255

    if($R -ge 255) { $R = 255 }
    if($G -ge 255) { $G = 255 }
    if($B -ge 255) { $B = 255 }

    return [RGB]::new($R, $G, $B)
}
function New-Scene {
    [Tri[]]$tris = @()
    $cubes = @()

    for($i = 0; $i -lt 3; $i++) {
        $cubes += New-Cube
    }

    $cubes[0].Translate(0, 0, 5)
    $cubes[1].Translate(0, -2, 5)
    $cubes[2].Translate(0, 2, 5)

    $cubes | foreach {
        $cube = $_
        [Tri[]]$triangles = MeshToTraingles $cube

        $triangles | foreach {
            $tris += $_
        }
    }
    return $tris
}

function New-CameraRays([int]$w, [int]$h) {
    $cam = [Camera]::new()

    $cam.Position = -$Up - $Right / 2 #-$Up / 2 + $Forward
    $cam.Right = $Right
    $cam.Fwd = $Forward
    $cam.Up = $Up
    $cam.Width = $w
    $cam.Height = $h

    $rays = New-Object 'Ray[,]' $w, $h

    for($x = 0; $x -lt $w; $x++) {
        for($y = 0; $y -lt $h; $y++) {
            $rays[$x,$y] = $cam.GetRay($x, $y)
        }
    }

    return ,$rays
}

function Run-Raytracer {
    [int]$width = 70
    [int]$height = 130


    [Tri[]]$scene = New-Scene
    $rays = New-CameraRays $width $height
    $floor = [Tri]::new([System.Numerics.Vector3]::new(1, -100, 0),[System.Numerics.Vector3]::new(1, 100, 0),[System.Numerics.Vector3]::new(1, -0.5, 1000));

    $scene += $floor
    
    $result = RayTracer 4 $width $height $rays $scene

    for($x = 0; $x -lt $width; $x++) {
        for($y = 0; $y -lt $height; $y++) {
            $color = Convert-VectorToRgb $result[$x, $y]
            Write-RGB -Text '  ' -BackgroundColor $color -NoNewLine
        }
        Write-RGB -text ' '
    }
}

Run-Raytracer
pause