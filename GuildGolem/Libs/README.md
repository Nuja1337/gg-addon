# The libraries in this folder

Three small libraries, each from its author's own repository, with its license beside it. There is no Ace3. The
addon's own base64 is `Core/Base64.lua`. `NOTICES.txt` in the folder above lists them for players.

| Library | Version | Where it came from | License |
|---|---|---|---|
| LibStub | minor 2 | [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3), `LibStub/LibStub.lua` at commit `cfde01bf4e917a3ef9bcf32a1cd7beefa1971564` ([the file](https://raw.githubusercontent.com/WoWUIDev/Ace3/cfde01bf4e917a3ef9bcf32a1cd7beefa1971564/LibStub/LibStub.lua)) | Public domain (`LibStub/LICENSE.txt`) |
| LibDeflate | 1.0.2-release, the latest release (Jun 26, 2020) | [SafeteeWoW/LibDeflate](https://github.com/SafeteeWoW/LibDeflate), tag `1.0.2-release`, commit `6831edcaa915154e7769d622e0de72ee5d25a882` ([the file](https://raw.githubusercontent.com/SafeteeWoW/LibDeflate/1.0.2-release/LibDeflate.lua)) | zlib License (`LibDeflate/LICENSE.txt`) |
| json.lua | 0.1.2 plus the string fix after it, commit `11077824d7cfcd28a4b2f152518036b295e7e4ce` (Apr 5, 2020) | [rxi/json.lua](https://github.com/rxi/json.lua) ([the file](https://raw.githubusercontent.com/rxi/json.lua/11077824d7cfcd28a4b2f152518036b295e7e4ce/json.lua)) | MIT (`json/LICENSE`) |

**LibStub's license file** is ours: the Ace3 repository has none for LibStub, whose header puts it in the public
domain. `LibStub/LICENSE.txt` quotes that header.

**json.lua is the commit after version 0.1.2, not the 0.1.2 tag,** since the tag has the bug the author fixed on Apr 5,
2020 ("Fixed bug in `parse_string`'s escape sequence handling", issue 22), and the addon reads strings people paste in.
The file still says `_version = "0.1.2"`. There has been no release since.

**LibDeflate needs no `bit` library** (it does its shifts with arithmetic), so the test stubs have none either. It has
no limit on how much a stream unpacks to, so `Core/ZlibSize.lua` counts first and `Core/Codec.lua` refuses a stream that
would pass 1 MiB before LibDeflate sees it.

## One change to one file

The game throws away what a file returns, and json.lua only returns its table, so the addon could not reach it. A block
of a few lines before the last line of `json/json.lua` (between `-- BEGIN GUILD GOLEM CHANGE` and `-- END GUILD GOLEM
CHANGE`) registers the table with LibStub, and the addon asks for it as `LibStub("json.lua")`. Nothing else in any
library has been changed. `npm test` (`test/libs.test.mjs`) takes that block out and checks that what is left is the
file below, byte for byte.

## Checksums

SHA-256 of every file in this folder as it is now. `npm test` fails if one differs.

```
26401bc42c26d1d1b6f7ad9410aa464edcbe4d32d74ebadeeecd8c0110236f7d  LibStub/LibStub.lua
b50d0d47c9718c0232a0b30029cba777e0e0b0b9781cbeece5e99946dc547f26  LibStub/LICENSE.txt
76f2114e527c2be1ac5cf768a68084946a3e19f63592834640020b7c9b5a450f  LibDeflate/LibDeflate.lua
acbecf8578f4febb766a1dd0217336e2e7ec19e66d13c907e38b01b1b727d7df  LibDeflate/LICENSE.txt
4ece1396c143dbe7d317a7d77cc8625c0078ca3c5e24bd63ff7b40f1b0e6bb2d  json/json.lua
e91de14a15c126e70df8d30132529199211b47c5c899f82285a2ee943748f6f2  json/LICENSE
```

## As published

SHA-256 of the files as their authors published them, at the commits above. For LibStub and LibDeflate that is the
same file. For json.lua it is the file without the block.

```
26401bc42c26d1d1b6f7ad9410aa464edcbe4d32d74ebadeeecd8c0110236f7d  LibStub/LibStub.lua
76f2114e527c2be1ac5cf768a68084946a3e19f63592834640020b7c9b5a450f  LibDeflate/LibDeflate.lua
acbecf8578f4febb766a1dd0217336e2e7ec19e66d13c907e38b01b1b727d7df  LibDeflate/LICENSE.txt
0eaccda57fabc0330736de25f45cf589821a42b5e0fe02e4e3125f7dc0bf2b7e  json/json.lua
e91de14a15c126e70df8d30132529199211b47c5c899f82285a2ee943748f6f2  json/LICENSE
```

## Updating one

Download the new file into an empty folder of its own, read it, and check what it does (a library that touches the
game's globals or the network does not belong here). Copy it in, add json.lua's block again if it is json.lua, and
update the version, commit and both checksum lists above. Run `npm test`.
