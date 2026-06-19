$testmode = $false

function printGrid {
  param([Object[,]]$grid)
  $out = ""
  for($i = 0; $i -lt $grid.GetLength(0); $i ++) {
    for($j = 0; $j -lt $grid.GetLength(1); $j ++) {
      if($grid[$i,$j] -eq ".") {
        $out += "#"
      } elseif($grid[$i,$j] -eq "-") {
        $out += " "
      } else {
        $out += $grid[$i,$j].ToString()
      }
    }
    $out += "`n"
  }
  $out
}

# input: .puz file
# goal 1: derive str[][] game, str[][] solution, str[] clues
# goal 2: map<str, str> clue number -> clues
# goal 3: getcluesoln(clue) -> to get solution to clue given "1d" type clue number
# goal 4: getcluework(clue) -> to get current state of clue solution in grid
# goal 5: fill(clue, guess) -> fill game with given string (space as blank?)
# goal 6: check() -> return # of wrong nonempty cells, checkclue(clue) -> similar but for specific clue
# goal 7: fix() -> empty incorrect cells in grid, fixclue(clue) -> ...c'mon.
# goal 8: show(clue,int) -> reveal int'th letter in clue (0-based), showclue(clue) -> reveal entire clue
# goal 9: hint(clue) -> reveal random letter in clue
# goal 10: playRound() -> prompt for every clue in order, showGame() -> printgrid gamegrid
# maybe goal: save manually-edited game[][] to .puz (requires checksum calculation)

$width = [int]"0x2c"
$height = [int]"0x2d"
$clueCt = [int]"0x2e"
$solnStart = [int]"0x34"

if($testmode) {
  $infile = Get-Item "[TESTFILE PATH]"
} else {
  $infile = Get-Item (Read-Host "Drag in .puz file").Replace('"', '')
}

$puzfile = Format-Hex -Path $infile
$rawBytes = @()
# Byte[] is easier to deal with than ByteCollection[]
for($i = 0; $i -lt $puzfile.Count; $i ++) {
  $rawBytes += $puzfile[$i].Bytes
}

$w = [int]$rawBytes[$width]
$h = [int]$rawBytes[$height]
$size = $w * $h

# find solution, set up solution grid
$spoilers = $rawBytes[($solnStart)..($solnStart + $size)]
$spoilerGrid = New-Object "object[,]" $h,$w
for($i = 0; $i -lt $h; $i ++) {
  for($j = 0; $j -lt $w; $j ++) {
    $spoilerGrid[$i, $j] = [System.Text.Encoding]::UTF8.GetString($spoilers[$i * $w + $j])
  }
}
# $text = ""
# for($i = 0; $i -lt $h; $i ++) {
#   for($j = 0; $j -lt $w; $j++) {
#     $text += $spoilerGrid[$i, $j]
#   }
#   $text += "`n"
# }
# Write-Output $text

$gameStart = $solnStart + $size
# same, but for the game grid
$game = $rawBytes[($gameStart)..($gameStart + $size)]
$gameGrid = New-Object "object[,]" $h,$w
for($i = 0; $i -lt $h; $i ++) {
  for($j = 0; $j -lt $w; $j ++) {
    $gameGrid[$i, $j] = [System.Text.Encoding]::UTF8.GetString($game[$i * $w + $j])
  }
}

# there'll be one \0 per clue, plus one for the Title, Author, and Copyright, plus Notes at the end
# so, looking for cluecount + 4 nuls
# this does ignore the "extra sections" region. I do not care.
$foundNuls = 0
for($i = $gameStart + $size; $foundNuls -lt ($rawBytes[$clueCt] + 4); $i ++) {
  if($rawBytes[$i] -eq 0) {
    $foundNuls += 1
  }
}

# -1 to undo the last iteration's $i++, and another -1 to get rid of the "" that would come from splitting "asdf`0"
$strSect = [System.Text.Encoding]::UTF8.GetString($rawBytes[($gameStart + $size) .. ($i-2)])
$strList = $strSect.split("`0")
# an extra -1 here to ignore the Notes section
$clueList = $strList[3 .. ($strList.Count - 2)]
# goal 1 complete
#################

# check if there's an across clue that starts at (x,y)
function takesAcross {
  param([int]$x, [int]$y)
  # check if it's a letter square
  if($gameGrid[$y,$x] -match "[^\.]") {
    # check if it's the leftmost letter square
    if(($x -eq 0) -or ($gameGrid[$y,($x-1)] -match "\.")) {
      # check if there's a letter to the right (no 1-long clues)
      if((($x + 1) -lt $w) -and ($gameGrid[$y,($x+1)] -match "[^\.]")) {
        # explicit return to force the func to exit
        return $true
      }
    }
  }
  return $false
}
function takesDown {
  param([int]$x, [int]$y)
  # check if it's a letter square
  if($gameGrid[$y,$x] -match "[^\.]") {
    # check if it's the uppermost letter square
    if(($y -eq 0) -or ($gameGrid[($y-1),$x] -match "\.")) {
      # check if there's a letter below (no 1-long clues)
      if((($y + 1) -lt $h) -and ($gameGrid[($y+1),$x] -match "[^\.]")) {
        # explicit return to force the func to exit
        return $true
      }
    }
  }
  return $false
}


# map of number+A/D -> [clue str, start x, start y]
$clueMap = [ordered]@{}
$gridNum = 1
$cluesDone = 0
for($y = 0; $cluesDone -lt $rawBytes[$clueCt]; $y ++) {
  for($x = 0; $x -lt $w; $x ++) {
    if((takesAcross $x $y) -or (takesDown $x $y)) {
      if(takesAcross $x $y) {
        $clueMap["$($gridNum)A"] = @($clueList[$cluesDone], $x, $y)
        $cluesDone ++
      }
      if(takesDown $x $y) {
        $clueMap["$($gridNum)D"] = @($clueList[$cluesDone], $x, $y)
        $cluesDone ++
      }
      $gridNum ++
    }
  }
}
# goal 2 complete
#################

# return the across-word in the grid starting at $x, $y
# assumes $x,$y is the first square
function getAcross {
  param([Object[,]]$grid, [int]$x, [int]$y)
  $out = ""
  # loop until end of grid or looking at a block square
  for($i = $x; ($i -lt $grid.GetLength(1)) -and ($grid[$y,$i] -match "[^\.]"); $i ++) {
    $out += $grid[$y,$i].ToString()
  }
  $out
}
function getDown {
  param([Object[,]]$grid, [int]$x, [int]$y)
  $out = ""
  # loop until end of grid or looking at a block square
  for($i = $y; ($i -lt $grid.GetLength(0)) -and ($grid[$i,$x] -match "[^\.]"); $i ++) {
    $out += $grid[$i,$x].ToString()
  }
  $out
}

function getClueSoln {
  param([string]$cluenum)
  $cluenum = $cluenum.ToUpper()
  $clue = $clueMap[$cluenum]
  if($cluenum -match "A") {
    getAcross $spoilerGrid $clue[1] $clue[2]
  } else {
    getDown $spoilerGrid $clue[1] $clue[2]
  }
}
function getClueWork {
  param([string]$cluenum)
  $cluenum = $cluenum.ToUpper()
  $clue = $clueMap[$cluenum]
  if($cluenum -match "A") {
    getAcross $gameGrid $clue[1] $clue[2]
  } else {
    getDown $gameGrid $clue[1] $clue[2]
  }
}
# goal 3 complete
# goal 4 complete
#################

function fill {
  param([string]$cluenum, [string]$guess)
  $cluenum = $cluenum.ToUpper()
  $space = getClueWork $cluenum
  $clue = $clueMap[$cluenum]
  $guess = ($guess -replace "\W", "-").ToUpper()
  # trim the guess if needed
  if($guess.Length -gt $space.Length) {
    $guess = $guess.Substring(0, $space.Length)
  }
  if($cluenum -match "A") {
    for($i = 0; $i -lt $guess.Length; $i ++) {
      $gameGrid[$clue[2],($clue[1]+$i)] = $guess[$i]
    }
  } else {
    for($i = 0; $i -lt $guess.Length; $i ++) {
      $gameGrid[($clue[2]+$i),$clue[1]] = $guess[$i]
    }
  }
}
# goal 5 complete
#################

function checkGrid {
  $outgrid = New-Object "object[,]" $h,$w
  for($i = 0; $i -lt $gameGrid.GetLength(0); $i++) {
    for($j = 0; $j -lt $gameGrid.GetLength(1); $j++) {
      # copy gameGrid's char if it's correct or blank
      if(($gameGrid[$i,$j] -eq $spoilerGrid[$i,$j]) -or ($gameGrid[$i,$j] -match "-")) {
        $outgrid[$i,$j] = $gameGrid[$i,$j]
      } else {
        # otherwise make it a !
        $outgrid[$i,$j] = "!"
      }
    }
  }
  return ,$outgrid
}
function errCount {
  $blankCt = 0
  $errCt = 0
  for($i = 0; $i -lt $gameGrid.GetLength(0); $i ++) {
    for($j = 0; $j -lt $gameGrid.GetLength(1); $j ++) {
      if($gameGrid[$i,$j] -match "-") {
        $blankCt += 1
      } elseif($gameGrid[$i,$j] -ne $spoilerGrid[$i,$j]) {
        $errCt += 1
      }
    }
  }
  "$($blankCt) blank squares, $($errCt) wrong squares"
}
function checkClue {
  param([string]$cluenum)
  $guess = getClueWork $cluenum
  $check = getClueSoln $cluenum
  $out = ""
  for($i = 0; $i -lt $guess.Length; $i ++) {
    if(($guess[$i] -match "-") -or ($guess[$i] -match $check[$i])) {
      $out += $guess[$i]
    } else {
      $out += "!"
    }
  }
  $out
}
# goal 6 complete
#################

function fix {
  for($i = 0; $i -lt $gameGrid.GetLength(0); $i ++) {
    for($j = 0; $j -lt $gameGrid.GetLength(1); $j ++) {
      if($gameGrid[$i,$j] -notmatch $spoilerGrid[$i,$j]) {
        $gameGrid[$i,$j] = "-"
      }
    }
  }
}
function fixClue {
  param([string]$cluenum)
  $repl = (checkClue $cluenum) -replace "!"," "
  fill $cluenum $repl
}
# goal 7 complete
#################

function show {
  param([string]$cluenum, [int]$index)
  $clueSoln = getClueSoln $cluenum
  $clueWork = getClueWork $cluenum
  if($index -ge $clueSoln.Length) { # index needs to be valid for the answer
    return ""
  }
  $clueWork = $clueWork.remove($index, 1).insert($index, $clueSoln[$index])
  fill $cluenum $clueWork
  return $clueWork
}
function showClue {
  param([string]$cluenum)
  $clueSoln = getClueSoln $cluenum
  fill $cluenum $clueSoln
  return $clueSoln
}
# goal 8 complete
#################

function hint {
  param([string]$cluenum)
  $clue = getClueSoln $cluenum
  show $cluenum (Get-Random -Maximum ($clue.Length))
}
# goal 9 complete
#################

function playRound {
  foreach($cluenum in $clueMap.Keys) {
    Write-Output "`nClue $($cluenum): $($clueMap[$cluenum][0])"
    Write-Output " Work: $(getClueWork $cluenum)"
    $guess = Read-Host "Guess"
    fill $cluenum $guess
  }
  Write-Output (printGrid $gameGrid)
}
function listClues {
  foreach($cluenum in $clueMap.Keys) {
    Write-Output "$($cluenum)`t$($clueMap[$cluenum][0]) ($(getClueWork $cluenum))"
  }
}
# goal 10 complete
##################

# post-10 observations:
# * crossword hard to see with #s printed: try . for unknown, [ ] for #
# * can't see clue #s: pick from coords and a/d
# * ^ coords need to be visibly displayed: new displaymode for game entirely
#
# goal 11: game display to show coords separated from grid
# goal 12: clue display from coords and direction

function dispGame {
  $out = "  "
  for($i = 0; $i -lt $gameGrid.GetLength(1); $i ++) {
    $out += "$($i % 10) "
  }
  for($i = 0; $i -lt $gameGrid.GetLength(0); $i ++) {
    $out += "`n$($i % 10) "
    for($j = 0; $j -lt $gameGrid.GetLength(1); $j ++) {
      if($gameGrid[$i,$j] -eq ".") { # black square
        $out += "  "
      } elseif($gameGrid[$i,$j] -eq "-") { # empty square
        $out += "- "
      } else {
        $out += "$($gameGrid[$i,$j].ToString()) " # letter
      }
    }
    $out += " $($i % 10)"
  }
  $out += "`n  "
  for($i = 0; $i -lt $gameGrid.GetLength(1); $i ++) {
    $out += "$($i % 10) "
  }
  $out
}
function dispCheck {
  $checkGrid = checkGrid
  $out = "  "
  for($i = 0; $i -lt $checkGrid.GetLength(1); $i ++) {
    $out += "$($i % 10) "
  }
  for($i = 0; $i -lt $checkGrid.GetLength(0); $i ++) {
    $out += "`n$($i % 10) "
    for($j = 0; $j -lt $checkGrid.GetLength(1); $j ++) {
      if($checkGrid[$i,$j] -eq ".") { # black square
        $out += "  "
      } elseif($checkGrid[$i,$j] -eq "-") { # empty square
        $out += "- "
      } else {
        $out += "$($checkGrid[$i,$j].ToString()) " # letter
      }
    }
    $out += " $($i % 10)"
  }
  $out += "`n  "
  for($i = 0; $i -lt $checkGrid.GetLength(1); $i ++) {
    $out += "$($i % 10) "
  }
  $out
}
# goal 11 complete
##################

function coordClue {
  param([int]$x, [int]$y, [string]$dir)
  if($dir -match "A") {
    if(($x -eq 0) -or ($gameGrid[$y,($x-1)] -match "\.")) { # leftmost in grid or next to a black square
      # find across cluenum whose clue matches the coordinates
      $cluenum = @($clueMap.Keys | Where-Object {($clueMap[$_][1] -eq $x) -and ($clueMap[$_][2] -eq $y) -and ($_ -match "A")})[0]
      Write-Output "$($cluenum)`t$($clueMap[$cluenum][0]) ($(getClueWork $cluenum))"
    } else {
      # move left one square and try again
      coordClue ($x-1) $y $dir
    }
  } else {
    if(($y -eq 0) -or ($gameGrid[($y-1),$x] -match "\.")) { # uppermost in grid or below to a black square
      # find across cluenum whose clue matches the coordinates
      $cluenum = @($clueMap.Keys | Where-Object {($clueMap[$_][1] -eq $x) -and ($clueMap[$_][2] -eq $y) -and ($_ -match "D")})[0]
      Write-Output "$($cluenum)`t$($clueMap[$cluenum][0]) ($(getClueWork $cluenum))"
    } else {
      # move up one square and try again
      coordClue $x ($y-1) $dir
    }
  }
}
# goal 12 complete
##################

# time to add a help command, and then work on checksums
# goal 13: help function to display other gamer functions
# goal 14: implement checksum function (can test on raw files)
# goal 15: save function - probably puzzle title + unix time(?)

function cmdHelp {
"Check"
"`terrCt`n`t`t display total number of blank and incorrect squares in the puzzle"
"`tcheckClue [cluenum]`n`t`t show clue work, with ! replacing incorrect letters"
"`tdispCheck`n`t`t show puzzle so far, with ! replacing incorrect letters"
"`tfixClue [cluenum]`n`t`t replace incorrect letters in clue work with blanks"
"`tfix`n`t`t replace all incorrect letters in grid with blanks"
"`thint [cluenum]`n`t`t reveal random letter in clue"
"`tshow [cluenum] [i]`n`t`t reveal correct letter at i'th position in clue (0-based)"
"`tshowClue [cluenum]`n`t`t reveal entire clue solution"
"Display"
"`tdispGame`n`t`t show puzzle so far"
"`tdispCheck`n`t`t show puzzle so far, with ! replacing incorrect letters"
"`tcmdHelp`n`t`t show this help message again"
"Play"
"`tplayRound`n`t`t go through all clues in numerical order, prompting an answer for each"
"`tfill [cluenum] [guess]`n`t`t fill out the indicated clue"
"`tlistClues`n`t`t display all clues' numbers, clue text, and work"
"`tcoordClue [x] [y] [direction]`n`t`t show the clue going [across/down] that passes through the coordinates"
"`tsaveGame`n`t`t save the game to a (mildly corrupted) .puz file"
}
# let's make a couple of aliases
function showCmds {
  cmdHelp
}
function showHelp {
  cmdHelp
}
# goal 13 complete
##################

# adapted from https://gist.github.com/coolreader18/e320113e6a3a818f23a1b15e46ba83ca#checksums
# which itself is adapted from https://code.google.com/archive/p/puz/wikis/FileFormat.wiki

function cksumRegion {
  param([int]$startIndex, [int]$len, [int]$cksum)
  for($i = 0; $i -lt $len; $i ++) {
    if(($cksum -band 1) -eq 1) {
      $cksum = ($cksum -shr 1) + "0x8000"
    } else {
      $cksum = $cksum -shr 1
    }
    $cksum += $rawBytes[($startIndex + $i)]
  }
  $cksum
}

function cksumString {
  param([string]$instr, [int]$cksum)
  $strbytes = @([System.Text.Encoding]::UTF8.GetBytes($instr))
  foreach($b in $strbytes) {
    if(($cksum -band 1) -eq 1) {
      $cksum = ($cksum -shr 1) + "0x8000"
    } else {
      $cksum = $cksum -shr 1
    }
    $cksum += $b
  }
  $cksum
}

# why won't it woooooorrrrrrrkkkkkkk

# okay, after literal days of beating my head against this wall, I'm giving up. The checksums on the strings
# just don't work. CIB? Fine. Game and Solution? Easy. Title, Author, Clues, etc? Nope!
# 
# So, I'm just gonna ignore them when writing the game state to the file. This will result in a corrupted
# .puz file if anyone actually looks at the checksums. So... don't do that. If you save a CrossParser game,
# just reopen it in CrossParser. I certainly don't check the checksums.

function saveGame {
  [byte[]]$outBytes = @($rawBytes)
  for($y = 0; $y -lt $h; $y ++) {
    for($x = 0; $x -lt $w; $x ++) {
        $outBytes[$gameStart + ($y * $w) + $x] = [byte][char]$gameGrid[$y,$x]
    }
  }
  $saveName = $strList[0] + " - save.puz" # saves as "[title] - save.puz"
  $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join '' # from https://stackoverflow.com/questions/23066783/
  $re = "[{0}]" -f [regex]::Escape($invalidChars)                      # strips invalid characters from the title to filenameify it
  $saveName = $saveName -replace $re
  $dirName = $infile.DirectoryName
  ,$outBytes | Set-Content "$($dirName)\$($saveName)" -Encoding Byte
}