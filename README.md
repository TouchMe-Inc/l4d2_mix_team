# About mix_team
Plugin adds voting for mixing teams. The mix_team plugin itself does not implement any mixing of players, but provides an API. 

## Commands
* `!mix <type>` - Start mix <type>.
* `!fmix <type>` - Force start mix <type>.
* `!unmix` - Abort the mix.

## Available mix types:
* `!mix random` - plugin [mt_random](/addons/sourcemod/scripting/mt_random.sp) - Shuffle players with random order.
* `!mix capitan` - plugin [mt_capitan](/addons/sourcemod/scripting/mt_capitan.sp) - Mix with captains.
* `!mix rank` - plugin [mt_capitan](/addons/sourcemod/scripting/mt_capitan.sp) - Mix based on [VersusStats](https://github.com/TouchMe-Inc/l4d2_versus_stats).
* `!mix exp` - plugin [mt_experience](/addons/sourcemod/scripting/mt_experience.sp) - Mix based on steam stats.
  
## Wiki
[How to create mix type?](https://github.com/TouchMe-Inc/l4d2_mix_team/wiki/How-to-create-mix-type%3F)

## Require
* Colors
* [NativeVotesRework](https://github.com/TouchMe-Inc/l4d2_nativevotes_rework)
* [SteamWorks](https://github.com/hexa-core-eu/SteamWorks) for [mt_experience](/addons/sourcemod/scripting/mt_experience.sp)

## Support
* [ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)
* [Left4DHooks](https://github.com/SilvDev/Left4DHooks)
