Notes about some special tests
==============================

# `bps-miniloader-book-rmmod.*`

`bps-miniloader-book.dat` contains examples for things added by the mod
"Miniloader". `bps-miniloader-book-rmmod.dat` is the same *after* this mod
has been removed. The binary format remembers some minimal information about
the uninstalled things. After reinstalling the mod the library objects are
converted back and can be used again without any issue. But the game's
export-format does not use this information and inserts placeholder things
like `entity-unknown`, `item-unknown` and similar and basically produces a
corrupt export. (Tested: Factorio 1.0.0)

`decode` *does* use the additional information and creates the same export
even with removed mods. Therefore the expected test result for 
`bps-miniloader-book-rmmod.dat` is the same as `bps-miniloader-book.dat`.
