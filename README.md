# CrossParser
Terminal-based crossword puzzle client, written in Powershell.

# How to Use
## Starting
In the directory you've saved CrossParser in, run `powershell -File ".\CrossParser.ps1"`. Or, in any other directory, do similarly with the full path to the script. This cannot be run from the File Explorer "Run with PowerShell" - at least, not if you intend to actually play the puzzle.

The program will prompt you to "Drag in [the] .puz file." Copying and pasting the full or relative path to the file works just as well, but the PowerShell terminal interprets dragging a file in as pasting the full path. This file will not be edited, merely read.

Once it's finished loading, you can play the game.

## Gameplay
All gameplay-facing functions can be seen with the `showHelp`, `showCmds`, or `cmdHelp` commands, which are aliases of each other. They are listed below, in order of how useful I personally find them from the start.  
Any time "clue number" is mentioned, it refers to the "[number][letter]" style of labeling a crossword clue, e.g. 13D, 7A, 20a. They will be capitalized when presented to the player, but may be input with a/d either upper- or lower-case.

* `playRound`  
Presents each clue to the player in numerical order (1A, 1D, 2D, 3D, 4A, 4D, etc). The player is shown the clue number, the clue text, and what letters (if any) are already filled in; they are then prompted to submit their guess. Characters in a guess will overwrite any existing letters on the grid for that clue, but only up to the length of the guess - for example, submitting an empty string (0 characters) will leave the grid untouched. Guesses that are too long are truncated to the length of the answer's size.  
Once all clues have been attempted, the state of the grid will be displayed, with spaces for blank letters and #s for black cells. Naturally, this function can be stopped early with Ctrl+C.
* `dispGame`  
Displays the grid the player has filled in so far, with dashes for blank letters and spaces for black cells. Each edge shows the ones-digit of the index of the rows and columns (e.g. the 14th column, index 13, has a 3 above and below it).
* `coordClue [column] [row] [direction]`  
Displays the clue number, clue text, and empty/filled letters of the clue which contains the cell at the given row and column, with the given direction of (A)cross or (D)own. Does not prompt the player to guess as `playRound` does.
* `fill [cluenumber] [guess]`  
Enters the guess string into the spaces for the given clue number. Like in `playRound`, it overwrites any existing letters, but only for the length of the guess, and too-long guesses are truncated.
* `listClues`  
Displays the clue number, clue text, and empty/filled letters of the clue for every clue in the puzzle, in numerical order. Does not prompt the player to guess.
* `showHelp`/`showCmds`/`cmdHelp`  
Displays a list of commands, along with brief summaries.

(to be continued)
